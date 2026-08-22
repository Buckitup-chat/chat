# Chunk Pipeline — Per-Drive Chunk Admission

Each physical storage device (SD, USB) runs its own chunk admission pipeline. All chunk bytes — from client uploads, drive-to-drive copies, and network sync — flow through a single serialized writer per drive. This eliminates filesystem write contention between chunk I/O and PostgreSQL on the same device.

See [pq_files.md §14](pq_files.md#14-implementation-history) for the v2 change that moved chunk bytes out of PostgreSQL.

## 1. Architecture Overview

```
               Drive A (e.g. SD)                          Drive B (e.g. USB1)
  ┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
  │  ChunkPipelineSupervisor             │   │  ChunkPipelineSupervisor             │
  │  ├─ ChunkWriter      (GenServer)     │   │  ├─ ChunkWriter      (GenServer)     │
  │  ├─ ReplicationListener (Postgrex)   │   │  ├─ ReplicationListener (Postgrex)   │
  │  ├─ DriveCopySource  (GenServer)     │   │  ├─ DriveCopySource  (GenServer)     │
  │  ├─ SyncSource       (GenServer)     │   │  ├─ SyncSource       (GenServer)     │
  │  ├─ TmpSweeper       (gen_statem)    │   │  ├─ TmpSweeper       (gen_statem)    │
  │  └─ DriveAnnouncer   (GenServer)     │   │  └─ DriveAnnouncer   (GenServer)     │
  │                                      │   │                                      │
  │  UploadSource ──┐                    │   │  UploadSource ──┐                    │
  │  (plain module) │  ┌──────────────┐  │   │  (plain module) │  ┌──────────────┐  │
  │  DriveCopySource┼─>│ ChunkWriter  │  │   │  DriveCopySource┼─>│ ChunkWriter  │  │
  │                 │  │  1 write/    │  │   │                 │  │  1 write/    │  │
  │  SyncSource ────┘  │  time ──>FS  │  │   │  SyncSource ────┘  │  time ──>FS  │  │
  │                    └──────────────┘  │   │                    └──────────────┘  │
  │                                      │   │                                      │
  │        ChunkStore A + PostgreSQL A   │   │        ChunkStore B + PostgreSQL B   │
  └──────────────────────────────────────┘   └──────────────────────────────────────┘
                                    │                 │
                                    └────drive copy───┘
                                      (reads across drives)
```

**Key invariant**: only one `ChunkStore.put` is in flight at a time per drive. ChunkWriter serializes all filesystem writes, so PostgreSQL (sharing the same device) never competes with multiple concurrent 4 MB writes.

Each drive is an independent storage domain — its own PG instance (port 5432 + offset), its own `ChunkStore` path, its own `missing_chunks` table.

## 2. Pipeline Components

### 2.1 ChunkWriter

GenServer, one per drive. Owns all `ChunkStore.put` calls for that drive.

Three prioritized **lanes** — `:upload`, `:drive_copy`, `:network_sync` — each backed by a `:queue`. Sources submit via `GenServer.call` (deferred reply — caller blocks until the chunk is written). ChunkWriter picks a lane, spawns a `Task` for the FS write, replies when done, picks next.

```
  submit(:upload, ...)       ─┐     ┌─> Task: ChunkStore.put ─┐
  submit(:drive_copy, ...)   ─┼──>  │   (one at a time)       │──> GenServer.reply(from, result)
  submit(:network_sync, ...) ─┘     │                         │    {:continue, :next_round}
                                     └─────────────────────────┘
```

Upload lane rejects with `{:busy, 2}` when its queue holds 2 items — the controller responds HTTP 429.

### 2.2 Sources

Three byte sources feed into each drive's ChunkWriter:

| Source | Type | Trigger | Lane |
|---|---|---|---|
| **UploadSource** | Plain module (not a process) | `FileChunkController.create` calls `UploadSource.submit/3` | `:upload` |
| **DriveCopySource** | GenServer via `ChunkSource` | PG replica trigger → ReplicationListener cast; drive mount; hourly poll | `:drive_copy` |
| **SyncSource** | GenServer via `ChunkSource` | `FileChunk.sync_after_persist` cast; peer reconnect; hourly poll | `:network_sync` |

**UploadSource** is a plain module — a one-line delegation to `ChunkWriter.submit(drive_id, :upload, body, meta)`. No GenServer needed: the Plug process blocks on the deferred reply directly.

**DriveCopySource** and **SyncSource** share a common `ChunkSource` behaviour+macro that provides the GenServer lifecycle, internal fetch/write pipeline, poll scheduling, sweep timers, and drain logic. Each source implements callbacks for its specific fetch strategy, source tracking, and query functions.

### 2.3 Supporting Processes

| Process | Type | Role |
|---|---|---|
| **ReplicationListener** | GenServer (wraps `Postgrex.Notifications`) | Listens for PG replica trigger notifications (`file_replicated`, `file_chunk_replicated`), calls `FileData` to fill `missing_chunks`, casts to DriveCopySource |
| **DriveAnnouncer** | GenServer (traps exit) | On init: broadcasts `{:drive_mounted, system_id}` on PubSub `"chunk_pipeline"`. On terminate: broadcasts `{:drive_unmounted, system_id}`. DriveCopySource subscribes to this topic. |
| **TmpSweeper** | `:gen_statem` | Hourly sweep of stale `.tmp` files from ChunkStore (crash residue from interrupted writes) |
| **GC** | GenServer (singleton, not per-drive) | Hourly garbage collection — purges chunk files and `missing_chunks` rows for deleted files and stale uploads (>48h) |

### 2.4 Data Flow Diagrams

**Client upload**:
```
Browser HTTP PUT
  → FileChunkController.create
    → UploadSource.submit(active_drive_id, body, meta)
      → ChunkWriter.submit(drive_id, :upload, body, meta)  [GenServer.call, blocks]
        → Task: ChunkStore.put(file_id, chunk_index, body, base_dir)  [FS write]
        ← :ok | {:busy, 2}
      ← result
    → insert file_chunks + upload_chunks rows (PG)
  ← HTTP 200 | 429
```

**Network sync** (Electric shape → SyncSource):
```
Electric shape arrives
  → ShapeWriter persists file_chunks row
    → FileChunk.sync_after_persist
      → FileData.fill_missing_chunk (populates data_hash/size on missing_chunks)
      → SyncSource.chunk_fetchable(drive_id, file_id, chunk_index, peer_url)  [cast]

SyncSource receives cast
  → enqueue {file_id, chunk_index, peer_url} in to_fetch
  → drain: start fetch Task (HTTP GET from peer)
    ← {:ok, body} → verify hash → enqueue in to_write
  → drain: start write Task
    → ChunkWriter.submit(drive_id, :network_sync, body, meta)  [blocks in task]
      → Task: ChunkStore.put  [FS write]
    ← :ok → delete missing_chunks row
```

**Drive-to-drive copy** (PG logical replication → DriveCopySource):
```
PG logical replication delivers files/file_chunks rows
  → PG replica trigger fires pg_notify
    → ReplicationListener receives notification
      → FileData.insert_missing_chunks_placeholders / fill_missing_chunk
      → DriveCopySource.chunk_fetchable(drive_id, file_id, chunk_index, system_id)  [cast]

DriveCopySource receives cast
  → enqueue {file_id, chunk_index, system_id} in to_fetch
  → drain: start fetch Task (ChunkStore.fetch from other drive's base_dir)
    ← {:ok, body} → verify hash → enqueue in to_write
  → drain: start write Task
    → ChunkWriter.submit(drive_id, :drive_copy, body, meta)  [blocks in task]
      → Task: ChunkStore.put  [FS write]
    ← :ok → delete missing_chunks row
```

## 3. Mechanisms

### 3.1 ChunkWriter Internals

**State**:
```elixir
%{
  drive_id: "sd" | {:via, ...},
  base_dir: nil | "/path/to/drive/files",
  queues: %{
    upload:       :queue.new(),   # items: {from, chunk_data, meta}
    drive_copy:   :queue.new(),
    network_sync: :queue.new()
  },
  wait_counters: %{drive_copy: 0, network_sync: 0},
  writing: nil  # nil | {task_ref, from, lane}
}
```

**Round loop** (`handle_continue(:next_round)`):

1. If `writing` is non-nil → return (write in flight).
2. `select_lane(state)` — override lane first, then strict priority (§3.2).
3. Pop head from selected lane's queue → `{from, chunk_data, meta}`.
4. Spawn `Task.async(fn -> ChunkStore.put(...) end)` — store `{task.ref, from, lane}` in `writing`.
5. Return `{:noreply, state}` — GenServer accepts new submissions while I/O runs.
6. `handle_info({ref, result})` — Task done. `GenServer.reply(from, result)`, clear `writing`, update counters, `{:continue, :next_round}`.
7. If `handle_info({:DOWN, ...})` — Task crashed. Reply `{:error, :write_failed}`, clear `writing`, continue.
8. If all queues empty → no `{:continue, :next_round}` — loop pauses until next `handle_call({:submit, ...})`.

**Single-writer guarantee**: the `writing` field gates step 1. Only one Task alive per ChunkWriter.

### 3.2 Source Selection Algorithm

Each round, ChunkWriter picks one lane. Two-stage selection:

**Override lane** (starvation prevention):

| Lane | Override after N rounds skipped | Rationale |
|---|---|---|
| `:upload` | never (always first in strict) | Interactive — user waiting |
| `:drive_copy` | **5** | Local I/O, fast, should not starve behind uploads |
| `:network_sync` | **97** | Lowest priority, but must eventually drain `missing_chunks` |

When multiple lanes qualify for override, strict priority order breaks the tie.

**Strict lane** (default): fixed priority `:upload` > `:drive_copy` > `:network_sync`. First with a non-empty queue wins.

**Wait counters**: incremented each round a lane is *not* selected and has a non-empty buffer. Reset to 0 on selection. Not incremented when the buffer is empty (nothing waiting = not starving). Starvation warning logged at 80% of threshold.

### 3.3 ChunkSource Internal Pipeline

DriveCopySource and SyncSource share an internal pipeline (via the `ChunkSource` macro) that decouples fetching from writing:

```
  event/cast/poll
       │
       ▼
   to_fetch (:queue)
       │
       ▼  ×N concurrent (fetch_cap = 3 × (max_to_write - to_write_len), up to 9)
   fetching (Task.Supervisor.async_nolink → source-specific fetch + hash verify)
       │
       ▼
   to_write (:queue, max 3 items)
       │
       ▼  ×2 concurrent (max_writing = 2)
   writing  (Task.Supervisor.async_nolink → ChunkWriter.submit)
       │
       ▼
   missing_chunks row deleted on success
```

**State** (injected by `ChunkSource.__using__`):
```elixir
%{
  drive_id: ...,
  repo: ...,
  sweep_timers: %{source_id => timer_ref},
  to_fetch: :queue.new(),       # {file_id, chunk_index, source_id}
  fetching: %{task_ref => {file_id, chunk_index}},
  to_write: :queue.new(),       # {file_id, chunk_index, body}
  to_write_len: 0,
  writing: %{task_ref => {file_id, chunk_index}},
  # ... plus source-specific fields from init_extra/1
}
```

**`drain/1`** runs after every state change: `drain_writing → refill_if_idle → drain_fetching`. This single function drives the entire pipeline forward.

**`refill_if_idle`**: when `to_fetch` is empty and `fetching` count < `fetch_cap`, auto-polls `missing_chunks` for more work. Sources self-replenish without waiting for the hourly timer.

**Fetch task**: calls the source's `fetch_chunk/4` callback, then `verify_hash` (compares `EnigmaPq.hash(body)` against `missing_chunks.data_hash`). On success: `{:fetched, file_id, chunk_index, body}`. On failure: `{:fetch_failed, ...}` → `increment_missing_chunk_attempts`.

**Write task**: `Task.Supervisor.async_nolink` → `ChunkWriter.submit(drive_id, writer_tag, body, meta)`. The source GenServer never blocks — the task process blocks on the deferred reply. On success: `{:written, ...}` → `FileData.delete_missing_chunk`. On failure: `{:write_failed, ...}` → increment attempts.

### 3.4 Backpressure

- **Uploads**: ChunkWriter rejects with `{:busy, 2}` when the `:upload` queue holds `@max_queue_size` (2) items. Controller responds HTTP 429 + `Retry-After`. The client retries — its PoP challenge has a TTL, so stalling indefinitely would expire it.
- **Fetch sources**: implicit via `to_write` capacity. When `to_write_len >= @max_to_write` (3), `fetch_cap` drops to 0 — no new fetches start. Each lane in ChunkWriter holds up to 2 items (deferred replies). Memory bound: 2 items × 3 lanes × ~4 MB = ~24 MB worst case per drive.
- **Deferred reply**: `GenServer.call` with `:infinity` timeout. The calling process (a Task from the source) is suspended by OTP until ChunkWriter selects and writes the chunk. No explicit semaphore needed.

### 3.5 Metadata Arrival Paths

Three independent paths deliver file/chunk metadata. Each activates exactly one source — no doubling.

| Path | Metadata delivery | Signal | Activates |
|---|---|---|---|
| **Client upload** | `FileChunkController.create` inserts `file_chunks` row | Controller calls `UploadSource.submit` | UploadSource |
| **Network sync** | Electric shapes via `ShapeConsumer` → `ShapeWriter` | `FileChunk.sync_after_persist` → casts to SyncSource | SyncSource |
| **Drive-to-drive** | PG logical replication delivers `files`/`file_chunks` rows | PG replica trigger → `pg_notify` → ReplicationListener → casts to DriveCopySource | DriveCopySource |

**PG replica triggers** (`ENABLE REPLICA TRIGGER`): the logical replication apply worker runs with `session_replication_role = 'replica'`. Replica triggers fire *only* for replicated rows — not for direct inserts from ShapeWriter or FileChunkController:

| Insert source | `sync_after_persist` fires? | PG replica trigger fires? |
|---|---|---|
| Electric shape (ShapeWriter) | Yes | No |
| Logical replication (drive-to-drive) | No | Yes |
| Local upload (FileChunkController) | No | No |

```sql
CREATE FUNCTION notify_file_replicated() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('file_replicated',
    json_build_object('file_id', NEW.file_id, 'chunk_count', NEW.chunk_count)::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER file_replicated_trigger
  AFTER INSERT ON files FOR EACH ROW
  EXECUTE FUNCTION notify_file_replicated();
ALTER TABLE files ENABLE REPLICA TRIGGER file_replicated_trigger;

CREATE FUNCTION notify_file_chunk_replicated() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('file_chunk_replicated',
    json_build_object('file_id', NEW.file_id, 'chunk_index', NEW.chunk_index,
                      'data_hash', NEW.data_hash, 'size', NEW.size)::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER file_chunk_replicated_trigger
  AFTER INSERT ON file_chunks FOR EACH ROW
  EXECUTE FUNCTION notify_file_chunk_replicated();
ALTER TABLE file_chunks ENABLE REPLICA TRIGGER file_chunk_replicated_trigger;
```

### 3.6 Batch Selection from `missing_chunks`

Both fetch sources select chunks in batches of up to **5** (`@batch_size`). Selection prioritizes low-attempt chunks, prefers same-domain sources, and randomizes within each group.

**DriveCopySource** (same-domain = has `source_drive_id`):
```sql
SELECT file_id, chunk_index, source_drive_id, peer_url FROM missing_chunks
WHERE data_hash IS NOT NULL
ORDER BY attempts,
  CASE WHEN source_drive_id IS NOT NULL THEN 0 ELSE 1 END,
  random()
LIMIT 5
```

**SyncSource** (same-domain = has `peer_url`):
```sql
SELECT file_id, chunk_index, peer_url, source_drive_id FROM missing_chunks
WHERE data_hash IS NOT NULL
ORDER BY attempts,
  CASE WHEN peer_url IS NOT NULL THEN 0 ELSE 1 END,
  random()
LIMIT 5
```

Three-level ordering: (1) lowest attempts first, (2) same-domain before cross-domain at same attempt level, (3) random within group — prevents both sources from selecting the same chunks when polling simultaneously.

Cross-domain chunks are normal. A DriveCopySource getting a chunk with only `peer_url` set skips the source-drive check and picks a random mounted drive. If no local drive has it, the chunk is skipped and `attempts` increments.

### 3.7 Collision Avoidance

DriveCopySource and SyncSource are activated by different callers — no shared event bus. During hourly polls, both scan `missing_chunks` but with different same-domain priorities and random ordering — unlikely to pick the same chunks.

If both do fetch the same chunk: `ChunkStore.put` is idempotent (file exists → overwrite with identical bytes), and `delete_missing_chunk` is idempotent (row already gone). Wasted work, not data corruption.

## 4. Details

### 4.1 `missing_chunks` Schema

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Parent file |
| `chunk_index` | INTEGER | Position in file |
| `data_hash` | TEXT, NULL | `fd_`-prefixed hash — NULL until `file_chunks` manifest row arrives |
| `size` | INTEGER, NULL | Expected byte size — NULL until manifest row arrives |
| `peer_url` | TEXT, NULL | Network peer that advertised this chunk (for SyncSource) |
| `source_drive_id` | TEXT, NULL | PG system_identifier of the replication source drive (for DriveCopySource). Set by ReplicationListener. |
| `attempts` | INTEGER, DEFAULT 0 | Retry bookkeeping — incremented by whichever source fails |
| `updated_at` | BIGINT | Last attempt or creation time (TimeKeeper) |
| | PK | `(file_id, chunk_index)` |

Indexes:

- `(attempts, updated_at)` WHERE `data_hash IS NOT NULL` — supports poll selection for both sources
- `(peer_url)` WHERE `data_hash IS NOT NULL AND peer_url IS NOT NULL` — supports SyncSource reconnect sweep
- `(source_drive_id)` WHERE `data_hash IS NOT NULL AND source_drive_id IS NOT NULL` — supports DriveCopySource reconnect sweep

### 4.2 ChunkStore

Filesystem storage for raw encrypted chunk bytes. Path layout: `{base_dir}/pq_files/{shard}/{file_id}/{zero_padded_index}`.

- **Sharding**: last 2 hex chars of `file_id` (after `f_` prefix) → 256 directories.
- **Write protocol**: `File.write(tmp_path, binary, [:raw, :sync])` + `File.rename(tmp, path)`.
  - **`:raw`** bypasses the Erlang file server (single process serializing all non-raw file I/O across the VM).
  - **`:sync`** flushes data to device before returning — prevents zero-length files on power loss before rename.
- **`base_dir`**: defaults to `Application.compile_env(:chat, :files_base_dir)`, overridable per drive. USB drives pass their mount-specific path.
- **`sweep_tmp_files/2`**: deletes `.tmp` files older than a threshold — cleanup for writes interrupted by crashes.
- **`available_space/0`**: queries `df` for free space on the chunk store device.

### 4.3 PG I/O Interaction

ChunkWriter does not gate PostgreSQL writes — each drive's PG manages its own I/O. But serializing chunk writes to one-at-a-time means PG never competes with multiple simultaneous 4 MB writes on the same device:

- **Upload path**: chunk FS write (ChunkWriter) → PG manifest insert (~5 KB row). Sequential within one round.
- **Drive copy / sync**: chunk FS write (ChunkWriter) → PG `missing_chunks` delete (tiny write). Sequential.
- **PG background** (WAL, autovacuum, checkpoint): runs concurrently with ChunkWriter but faces less contention.
- **Cross-drive reads**: DriveCopySource reads from *another* drive's ChunkStore — does not contend with the local drive's writer or PG.

### 4.4 Drive Identity

Each drive is identified by its PostgreSQL **system identifier** — a unique 64-bit integer assigned at `initdb`, queried via `SELECT system_identifier FROM pg_control_system()`. This is stable across reboots and unique across drives.

**DriveAnnouncer**: per-drive GenServer that queries the drive's PG for its system_identifier, broadcasts `{:drive_mounted, system_id}` on PubSub `"chunk_pipeline"`, and on terminate broadcasts `{:drive_unmounted, system_id}`.

**Drive discovery** (DriveCopySource): on init and on mount events, scans the filesystem for mounted drives (`/media/sd*`), queries each drive's PG for its system_identifier, builds a map `%{system_id => base_dir}` of other drives' chunk stores.

### 4.5 Lifecycle

#### 4.5.1 Supervision

```
# Host (dev) — internal drive only
Chat.Application supervisor
  └─ Chat.RepoStarter (DynamicSupervisor, starts after Repo + migrations)
       └─ ChunkPipelineSupervisor (drive_id: :internal, repo: Chat.Repo)
            ├─ ChunkWriter
            ├─ ReplicationListener
            ├─ DriveCopySource
            ├─ SyncSource
            ├─ TmpSweeper
            └─ DriveAnnouncer

# Target — internal drive
Platform.App.DatabaseSupervisor
  └─ ... (Repo, Migrations, ...)
  └─ ChunkPipelineSupervisor (drive_id: :internal, repo: Chat.Repo)

# Target — USB drives
Platform.App.Drive.MainDbSupervisor (per USB drive)
  └─ ... (Repo, Migrations, ...)
  └─ ChunkPipelineSupervisor (drive_id: device, base_dir: ..., repo: ...)
```

Process names are scoped per drive via `{:via, Registry, {ChunkPipelineRegistry, {role, drive_id}}}`.

#### 4.5.2 Crash Recovery

Supervisor restarts crashed processes. ChunkWriter's queue state is lost — deferred callers receive `{:EXIT, ...}` and retry. If the in-flight write Task crashes, `handle_info({:DOWN, ...})` clears `writing`, replies `{:error, :write_failed}`, and triggers the next round.

For fetch sources: crashed fetch/write tasks are caught by `handle_info({:DOWN, ...})`, which records a failure (`increment_missing_chunk_attempts`) and continues draining.

#### 4.5.3 Drive Mount/Unmount

**Mount**: Platform starts the drive's `ChunkPipelineSupervisor`. DriveAnnouncer broadcasts `:drive_mounted`. DriveCopySources on other drives receive the PubSub message, re-scan drives, and schedule a reconnect sweep (5-second timer — see §4.6).

**Unmount**: Platform stops the drive's pipeline group. DriveAnnouncer broadcasts `:drive_unmounted`. DriveCopySources on other drives remove this drive from their source maps. In-flight calls to the stopped ChunkWriter receive `{:EXIT, ...}`. Chunks whose `source_drive_id` pointed to the unmounted drive remain in `missing_chunks` — subsequent fetches try random available drives.

#### 4.5.4 Main DB Switch and Upload Routing

`FileChunkController` resolves the active drive's UploadSource at request time via `ChunkPipeline.active_drive_id/0`. `Chat.Db.Switching` updates this on switch. In-flight uploads complete on the old drive; new requests route to the new drive.

### 4.6 Source Reconnect Sweep

When a source becomes available (peer reconnects, drive remounts), the corresponding source schedules a 5-second timer. If the source is still connected when the timer fires, the source queries `missing_chunks` for rows matching that source and enqueues them for fetching.

The 5-second delay filters flapping sources — a drive that mounts and unmounts in 2 seconds never triggers a sweep.

**SyncSource** — peer reconnect:
```sql
SELECT file_id, chunk_index FROM missing_chunks
WHERE peer_url = $1 AND data_hash IS NOT NULL
ORDER BY attempts, updated_at
```

**DriveCopySource** — drive remount:
```sql
SELECT file_id, chunk_index FROM missing_chunks
WHERE source_drive_id = $1 AND data_hash IS NOT NULL
ORDER BY attempts, updated_at
```

### 4.7 Fallback Poll

On source start and once per hour, DriveCopySource and SyncSource poll `missing_chunks` for fetchable rows. This catches anything that events missed (crash recovery, race conditions, delayed replication).

`refill_if_idle` also triggers a poll whenever the source's `to_fetch` queue drains — sources actively pull new work rather than waiting for the next hourly tick.

### 4.8 `ChunkSource` Behaviour

Callbacks each source must implement:

| Callback | Purpose |
|---|---|
| `registry_key()` | Registry key atom (`:drive_copy_source`, `:sync_source`) |
| `writer_tag()` | ChunkWriter lane atom (`:drive_copy`, `:network_sync`) |
| `init_extra(opts)` | Source-specific state fields |
| `on_init(state)` | Optional post-init hook (subscribe to PubSub, scan drives) |
| `handle_source_cast(event, state)` | Handle connect/disconnect events → `{:source_connected, id, state}` or `{:source_disconnected, id, state}` |
| `source_connected?(state, id)` | Check if a source is currently available |
| `can_poll?(state)` | Optional guard for polling (DriveCopySource: only when other drives exist) |
| `poll_query(limit, repo)` | Query `missing_chunks` for fetchable rows |
| `sweep_query(source_id, repo)` | Query `missing_chunks` for a specific source |
| `chunk_source_id(mc)` | Extract source identifier from a `missing_chunks` row |
| `fetch_chunk(state, file_id, chunk_index, source_id)` | Fetch bytes from the source → `{:ok, body}` or `{:error, reason}` |
| `handle_extra_info(msg, state)` | Optional handler for unmatched messages |

### 4.9 Observability

- **Starvation warnings**: logged when a wait counter crosses 80% of its override threshold.
- **Source list changes**: logged when DriveCopySource/SyncSource gain or lose a source (drive mount/unmount, peer connect/disconnect).
- **Fetch/write failures**: logged with file_id and chunk_index on hash mismatch or fetch error.

### 4.10 Replaced Components

- **`ElectricIngestThrottle`**: counting semaphore that gated concurrent chunk ingest — removed. ChunkWriter's single-writer model subsumes its purpose.
- **`ChunkFetcher`**: direct `ChunkStore.put` calls for network sync — replaced by SyncSource.

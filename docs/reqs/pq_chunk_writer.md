# ChunkWriter — Serialized Chunk Admission Pipeline

Per-drive writer pipeline for admitting chunk bytes to `ChunkStore`. Each physical storage device (SD, USB1, USB2) runs its own `{ChunkWriter, UploadSource, DriveCopySource, SyncSource}` group. All three byte sources feed into the drive's writer, which serializes filesystem writes — reducing FS contention with that drive's PostgreSQL instance.

See [pq_files.md §14](pq_files.md#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes) for the v2 architecture that moved chunk bytes out of PostgreSQL.

## 1. Problem

Filesystem writes are a limited resource on each storage device. Three independent subsystems produce chunk bytes for a drive's `ChunkStore`:

| Source | Current writer | Trigger |
|---|---|---|
| **Client upload** | `FileChunkController.create` → `ChunkStore.put` | HTTP PUT from browser |
| **Drive copy** | (not yet implemented) | Co-located drive has chunks this drive needs |
| **Network sync** | `ChunkFetcher` → `ChunkStore.put` | `missing_chunks` rows from Electric |

Each source calls `ChunkStore.put` independently. On a single USB/SD device, concurrent 4 MB writes thrash the filesystem — and that drive's PostgreSQL instance writes to the same filesystem (WAL, heap, TOAST for manifest rows). Serializing chunk writes per drive eliminates FS write contention between sources and reduces pressure on PG's I/O path.

Each drive is an independent storage domain with its own PG instance (port 5432 + offset), its own `ChunkStore` path, and its own `missing_chunks` table. The pipeline must be per-drive.

## 2. Architecture

```
               Drive A (e.g. SD)                          Drive B (e.g. USB1)
  ┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
  │                                      │   │                                      │
  │  UploadSource ──┐                    │   │  UploadSource ──┐                    │
  │                 │  ┌──────────────┐  │   │                 │  ┌──────────────┐  │
  │  DriveCopySource┼─>│ ChunkWriter  │  │   │  DriveCopySource┼─>│ ChunkWriter  │  │
  │                 │  │ (GenServer)  │  │   │                 │  │ (GenServer)  │  │
  │  SyncSource ────┘  └──────┬───────┘  │   │  SyncSource ────┘  └──────┬───────┘  │
  │                           │          │   │                           │          │
  │                    ChunkStore A      │   │                    ChunkStore B      │
  │                    PostgreSQL A      │   │                    PostgreSQL B      │
  └──────────────────────────────────────┘   └──────────────────────────────────────┘
                                    │                 │
                                    └────drive copy───┘
                                      (reads across drives)
```

**ChunkWriter** is a GenServer, one per drive. It owns all `ChunkStore.put` calls for that drive — no other code writes to that drive's ChunkStore directly.

Each **source** is a permanent GenServer (always running, see §9) that acts as a sink — work arrives via events, not polling. Sources submit to their drive's ChunkWriter. See §5 for metadata arrival paths and how each source is activated.

### 2.1 Mechanism: GenServer + Deferred Reply + `:queue` + Task

No external dependencies — the pipeline uses OTP/stdlib primitives:

- **Deferred reply**: sources call `GenServer.call(writer, {:submit, lane, chunk_data, meta})`. The writer does **not** reply immediately — it holds the caller's `from` reference (`{:noreply, state}` from `handle_call`) and buffers the request. The caller blocks until the writer selects and writes the chunk, then receives the result via `GenServer.reply(from, result)`.
- **`:queue`**: Erlang's double-ended queue (O(1) push/pop) backs each source lane's buffer inside ChunkWriter's state. Three queues: `:upload`, `:drive_copy`, `:network_sync`.
- **`handle_continue`**: after lane selection, the writer spawns a `Task` for the FS write and returns immediately — the GenServer stays responsive for accepting new submissions while I/O is in flight. When the Task completes, `handle_info` receives the result, replies to the original caller, and triggers the next round.
- **Delegated I/O**: `ChunkStore.put` runs inside a `Task` (one at a time per drive), not in the GenServer process. This separates queue management (microseconds) from filesystem I/O (~200–400 ms for 4 MB on SD/USB). Without delegation, incoming `handle_call({:submit, ...})` messages would pile up unprocessed in the mailbox for the full duration of each write.

```elixir
# ChunkWriter state (conceptual)
%{
  drive_id: "sd",
  queues: %{
    upload:       :queue.new(),   # items: {from, chunk_data, meta}
    drive_copy:   :queue.new(),
    network_sync: :queue.new()
  },
  wait_counters: %{drive_copy: 0, network_sync: 0},
  writing: nil  # nil | {task_ref, from, lane} — tracks the in-flight write
}
```

**Flow for one round**:

1. `handle_continue(:next_round, state)` — if `writing` is non-nil, return (write already in flight). Select source lane per §4.
2. Pop head from selected lane's `:queue` → `{from, chunk_data, meta}`
3. Spawn `Task`: `ChunkStore.put(meta.file_id, meta.chunk_index, chunk_data)` (FS write — see §7.1). Store `{task_ref, from, lane}` in `writing`.
4. Return `{:noreply, state}` — GenServer is free to accept new submissions via `handle_call`.
5. `handle_info({ref, result})` — Task completed. `GenServer.reply(from, result)` unblocks the source's caller.
6. Set `writing` to `nil`. Update wait counters per §4.3.
7. Return `{:noreply, state, {:continue, :next_round}}` — loop continues.
8. If all queues are empty → `{:noreply, state}` — loop pauses until next `handle_call` submit triggers `{:continue, :next_round}`.

**Single-writer guarantee**: only one Task is alive at a time per ChunkWriter — the `writing` field gates step 1. This preserves the one-write-at-a-time-per-drive invariant while keeping the GenServer responsive.

## 3. Source Prefetch and Backpressure

Each source's lane inside ChunkWriter holds up to **2 buffered chunks** (the deferred-reply items in its `:queue`). When the writer selects a lane, it pops the head, writes it, and replies to the caller. The source (or its upstream caller) then submits the next chunk.

```
ChunkWriter :queue for one lane (capacity 2):

  [ {from₁, chunk N+1, meta} | {from₂, chunk N+2, meta} ]
        ↑
    Writer pops chunk N+1 when this lane is selected
    GenServer.reply(from₁, :ok) unblocks caller₁
    Caller₁ does post-write bookkeeping, then submits chunk N+3
```

**Why 2**: one chunk is always ready for the writer (no idle gap between rounds), the second absorbs variance in source I/O latency. More than 2 wastes memory (each chunk is ~4 MB, so 2 items × 3 lanes = ~24 MB worst case per drive — acceptable on 4 GB RAM).

**Backpressure** is implicit in the deferred-reply model: when a lane's `:queue` holds 2 items, the next `GenServer.call` from that source blocks — the caller process is suspended by OTP until a slot opens and the call is replied to. No explicit semaphore or rejection needed. This naturally throttles network fetches and drive reads. Exception: UploadSource rejects immediately with `{:busy, retry_after}` when full (§5.1).

## 4. Source Selection

Each round, ChunkWriter picks one source to take a chunk from. Selection has two lanes evaluated in order:

### 4.1 Override Lane (starvation prevention)

A source is promoted to the override lane when it has waited too many rounds since its last write. Override thresholds:

| Source | Override after | Rationale |
|---|---|---|
| Client upload | — (never overridden, always strict-first) | Interactive — user is waiting |
| Drive copy | **5 rounds** | Local I/O, fast source, should not starve behind a stream of uploads |
| Network sync | **97 rounds** | Lowest priority, but must make progress to drain `missing_chunks` |

When multiple sources qualify for override, **strict lane order** breaks the tie (drive copy before network sync).

### 4.2 Strict Lane (default priority)

When no override applies, sources are selected in fixed priority order:

1. **Client upload** — interactive, user is waiting for HTTP response
2. **Drive copy** — local, fast, but not user-blocking
3. **Network sync** — background, tolerates latency

The first source with a non-empty buffer wins.

### 4.3 Round Counter

Each source (except client upload) carries a **wait counter**:

- Incremented by 1 every round the source is **not** selected (and has a non-empty buffer)
- Reset to 0 when the source **is** selected
- Not incremented when the source's buffer is empty (nothing to write — not starving)

Override triggers when `wait_counter >= threshold`.

### 4.4 Selection Algorithm

Runs inside `handle_continue(:next_round, state)`:

```
each round:
  # Override lane
  overrides = lanes
    |> where :queue is non-empty
    |> where wait_counter >= threshold
    |> sort by strict priority

  if overrides is non-empty:
    selected = first(overrides)
  else:
    # Strict lane
    selected = lanes
      |> sort by strict priority
      |> first where :queue is non-empty

  if selected is nil:
    # All queues empty — pause loop.
    # Next handle_call {:submit, ...} triggers {:continue, :next_round}.
    return {:noreply, state}

  {from, chunk_data, meta} = :queue.out(selected.queue)
  result = ChunkStore.put(meta.file_id, meta.chunk_index, chunk_data)
  GenServer.reply(from, result)

  for each other lane with non-empty queue:
    lane.wait_counter += 1
  selected.wait_counter = 0

  return {:noreply, state, {:continue, :next_round}}
```

## 5. Sources

Each source is a permanent GenServer (one per drive) that acts as a **sink** — work arrives via events, not polling. The source is responsible for its own validation and post-write bookkeeping.

All three sources per drive are always running. They react to events when work arrives and are idle otherwise. `missing_chunks` table polling is a **fallback only** — on source start and once per hour — not the primary activation path.

### 5.0 Metadata Arrival Paths

Three independent paths deliver file/chunk metadata to a drive. Each path has its own mechanism for activating the appropriate source:

| Path | Metadata delivery | Signal | Activates |
|---|---|---|---|
| **Client upload** | `FileChunkController.create` inserts `file_chunks` row directly | Controller calls `UploadSource.submit` | UploadSource |
| **Network sync** | Electric shapes via `ShapeConsumer` → `ShapeWriter` | `sync_after_persist` → PubSub broadcast | SyncSource |
| **Drive-to-drive** | PG logical replication delivers `files`/`file_chunks` rows | PG replica trigger → `pg_notify` → listener | DriveCopySource |

#### 5.0.1 Network Sync Activation

When `ShapeWriter` persists a `file_chunks` row via Electric sync, `FileChunk.sync_after_persist` calls `FileData.fill_missing_chunk` — populating `data_hash` and `size` on the `missing_chunks` placeholder (preseeded when the `files` manifest arrived). At this point the chunk is fetchable. `fill_missing_chunk` casts directly to the drive's SyncSource:

```elixir
SyncSource.chunk_fetchable(drive_id, file_id, chunk_index, peer_url)
# → GenServer.cast({:via, Registry, {ChunkRegistry, {:sync_source, drive_id}}}, ...)
```

SyncSource receives the cast and immediately begins fetching.

#### 5.0.2 Drive-to-Drive Activation (PG Replica Triggers)

Logical replication delivers `files` and `file_chunks` rows at the PG wire protocol level — no Elixir callbacks fire. To bridge this gap, **PG triggers** on the subscriber database call `pg_notify`:

```sql
-- On files INSERT: notify so listener can preseed missing_chunks placeholders
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

-- On file_chunks INSERT: notify so listener can fill missing_chunk hash/size
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

**`ENABLE REPLICA TRIGGER`**: the logical replication apply worker runs with `session_replication_role = 'replica'`. A replica trigger fires **only** for replicated rows — not for direct inserts from `ShapeWriter` or `FileChunkController`. This prevents doubling with the Electric `sync_after_persist` callbacks:

| Insert source | `sync_after_persist` fires? | PG replica trigger fires? |
|---|---|---|
| Electric shape (`ShapeWriter`) | Yes | No |
| Logical replication (drive-to-drive) | No | Yes |
| Local upload (`FileChunkController`) | No | No |

No doubling. Each path has exactly one callback. Local upload correctly fires neither — that drive already has the bytes.

A **`Postgrex.Notifications` listener** (one per drive, in the pipeline supervisor) subscribes to both channels and:

1. On `file_replicated` → calls `FileData.insert_missing_chunks_placeholders` (same logic as `File.sync_after_persist`). The `source_drive_id` is the drive that published the replication — the listener sets it as provenance for DriveCopySource (see §6).
2. On `file_chunk_replicated` → calls `FileData.fill_missing_chunk` (same logic as `FileChunk.sync_after_persist`) → casts to `DriveCopySource.chunk_fetchable(drive_id, ...)` directly.

#### 5.0.3 Fallback Poll and Reconnect Sweep

On source start and once per hour, DriveCopySource and SyncSource scan `missing_chunks` for any fetchable rows that events may have missed (crash recovery, race conditions, delayed replication). This is a safety net, not the primary work driver.

Additionally, when a source becomes available again (peer reconnects or drive remounts) and stays up for 5 seconds, the corresponding source scans `missing_chunks` for chunks whose preferred source matches — but only if its writer lane is idle (see §5.6). This is the fast path for recovering from temporary source unavailability without competing with already-queued work.

### 5.1 UploadSource (`:upload` lane)

- **Always running**: one per drive, started in the drive's pipeline supervisor.
- **Receives from**: `FileChunkController.create` — the controller validates signature/hash, then calls `UploadSource.submit(chunk_data, meta)` on the **active drive's** UploadSource (see §8.2 for main DB switching).
- **Submit flow**: `UploadSource` forwards to its drive's ChunkWriter via `GenServer.call` (deferred reply). The Plug process blocks until the chunk is written.
- **On reply (`:ok`)**: controller inserts `file_chunks` manifest row + `upload_chunks` bookkeeping row into PG, returns HTTP 200 to client.
- **Backpressure**: when 2 uploads are already queued in ChunkWriter, `UploadSource.submit` returns `{:busy, retry_after}` immediately — the controller responds with **429 + `Retry-After` header**. The client must not block indefinitely: its PoP challenge has a TTL, and a stalled request would expire it. This replaces `ElectricIngestThrottle` (§8).

### 5.2 DriveCopySource (`:drive_copy` lane)

- **Always running**: one per drive, started in the drive's pipeline supervisor. Idle until other drives are available.
- **Maintains**: a list of **other drives' `{drive_id, chunk_store_path}` pairs** — updated when drives mount/unmount. Does not include its own drive.
- **Activated by**:
  1. **`DriveCopySource.chunk_fetchable/4` cast** — when `fill_missing_chunk` fires (from PG replica trigger listener, see §5.0.2), the listener casts directly to DriveCopySource, which checks if any local drive has the bytes.
  2. **Drive mount** — when a new drive becomes available, scans existing `missing_chunks` for locally resolvable chunks.
  3. **Fallback poll** — on start and hourly (§5.0.3).

**`missing_chunks` provenance**: when `missing_chunks` rows are created via the PG replica trigger listener (§5.0.2), the `source_drive_id` column is set to the drive that published the replication. This gives DriveCopySource a direct hint for where to read bytes.

**Batch selection**: each turn, DriveCopySource selects up to **5 chunks** from `missing_chunks` (see §5.5 for the shared selection query). Chunks with `source_drive_id` set (same-domain) are prioritized over chunks with only `peer_url` (cross-domain). Randomization within each priority group ensures DriveCopySource and SyncSource diverge in selection order.

**Fetch strategy** (drives only — never touches network, one source per attempt):

1. If the chunk has a `source_drive_id` (same domain) and that drive is mounted → read from it
2. Otherwise (drive not mounted, or no `source_drive_id`) → pick **one** random mounted drive → read from it
3. If the chosen drive doesn't have it → increment `attempts`, skip (next attempt may pick a different random drive)
4. If found but hash mismatch → increment `attempts`, skip

On successful write reply from ChunkWriter → delete `missing_chunks` row.

### 5.3 SyncSource (`:network_sync` lane)

- **Always running**: one per drive, replaces current `ChunkFetcher`'s direct `ChunkStore.put` calls.
- **Maintains**: a list of **known network peer URLs** — updated as peers connect/disconnect.
- **Activated by**:
  1. **`SyncSource.chunk_fetchable/4` cast** — when `fill_missing_chunk` fires (from `FileChunk.sync_after_persist` during Electric sync, see §5.0.1), `sync_after_persist` casts directly to SyncSource with the `peer_url`. SyncSource immediately begins fetching.
  2. **Fallback poll** — on start and hourly (§5.0.3).

**Batch selection**: each turn, SyncSource selects up to **5 chunks** from `missing_chunks` (see §5.5 for the shared selection query). Chunks with `peer_url` set (same-domain) are prioritized over chunks with only `source_drive_id` (cross-domain). Randomization within each priority group ensures SyncSource and DriveCopySource diverge in selection order.

**Fetch strategy** (network peers only — never touches local drives, one source per attempt):

1. If the chunk has a `peer_url` (same domain) and that peer is online → fetch from it
2. Otherwise (peer offline, or no `peer_url`) → pick **one** random online peer → fetch from it
3. If the chosen peer doesn't have it or fetch fails → increment `attempts`, skip (next attempt may pick a different random peer, or retry when a peer reconnects — see §5.6)

- **Validation**: hash check against `data_hash` (unchanged from current `ChunkFetcher.admit_chunk`).
- **On reply (`:ok`)**: deletes `missing_chunks` row.

### 5.4 Collision Avoidance Between DriveCopySource and SyncSource

Each source is activated by a different caller — no shared event bus:

- **Natural separation by path**: Electric sync casts to SyncSource; PG replica trigger listener casts to DriveCopySource. Each source handles its natural path without overlap.
- **Fallback poll overlap**: during hourly polls, both scan the same `missing_chunks` table. They select from the "least attempts" pool with random ordering — unlikely to pick the same chunk.
- **No hard lock**: if both do fetch the same chunk, the second `ChunkStore.put` for an already-written chunk is idempotent (file exists, no-op or overwrite with identical bytes). The second `missing_chunks` delete is also idempotent (row already gone). Wasted work, not data corruption.

### 5.5 Batch Selection from `missing_chunks`

Both DriveCopySource and SyncSource select chunks in small batches — **up to 5 per turn**. The selection prioritizes low-attempt chunks first, prefers same-domain chunks within the same attempt level, and randomizes within each group.

#### 5.5.1 Selection Query

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

#### 5.5.2 Selection Semantics

The three-level ordering — `attempts`, `source_type`, `random()` — produces this behavior:

1. **Lowest attempts first**: fresh chunks before retried ones. A chunk at attempt 0 always beats attempt 1, regardless of source type.
2. **Same-domain before cross-domain** (within same attempt level): DriveCopySource prefers chunks that have a `source_drive_id` hint — it can check the specific drive first. Cross-domain chunks (originally network, no `source_drive_id`) are still eligible but come after same-domain ones at the same attempt count.
3. **Random within group**: prevents DriveCopySource and SyncSource from selecting the same 5 chunks when both poll simultaneously. Also distributes work across different files/chunks rather than always picking the same deterministic order.

**Cross-domain chunks are normal, not exceptional.** A DriveCopySource getting a chunk with only `peer_url` set simply skips the initial-source check (no drive hint to try) and goes straight to picking a random mounted drive. The chunk may or may not be on a local drive — if not, it gets skipped and `attempts` increments.

### 5.6 Source Reconnect Sweep

When a source becomes available again, chunks that were skipped because their preferred source was offline get another chance — but only when the source's lane is idle and the source has been stable for at least 5 seconds.

**Two conditions must be met before a sweep fires:**

1. **Lane idle**: the source's `:queue` in ChunkWriter is empty — no work already in flight or buffered for this lane. If the lane has pending items, the source is already busy and the sweep would just compete with existing work.
2. **Source stable for 5 seconds**: a `Process.send_after(self(), {:sweep, source_id}, 5_000)` is scheduled when the source appears. If the source disconnects before the timer fires, the message is ignored (source no longer in known list). This filters out flapping sources — a drive that mounts and unmounts in 2 seconds never triggers a sweep.

#### 5.6.1 Peer Reconnect → SyncSource

When a network peer reconnects, SyncSource schedules a 5-second timer for that peer. When the timer fires — if the peer is still online and the `:network_sync` lane is idle — SyncSource queries:

```sql
SELECT file_id, chunk_index FROM missing_chunks
WHERE peer_url = $1 AND data_hash IS NOT NULL
ORDER BY attempts, updated_at
```

Each matched chunk is re-triggered for fetching. If the lane is not idle when the timer fires, the sweep is skipped — existing work will drain naturally, and the hourly poll catches anything left.

#### 5.6.2 Drive Remount → DriveCopySource

When a USB drive remounts, DriveCopySource schedules a 5-second timer for that drive. When the timer fires — if the drive is still mounted and the `:drive_copy` lane is idle — DriveCopySource queries:

```sql
SELECT file_id, chunk_index FROM missing_chunks
WHERE source_drive_id = $1 AND data_hash IS NOT NULL
ORDER BY attempts, updated_at
```

Each matched chunk is re-triggered. Same skip-if-busy rule as §5.6.1.

#### 5.6.3 Lane Idle Check

Sources need to know if their lane in ChunkWriter is idle. ChunkWriter exposes this via:

```elixir
ChunkWriter.lane_idle?(drive_id, :network_sync)
# → true if the lane's :queue is empty and no write is in flight for this lane
```

This is a synchronous `GenServer.call` — lightweight (no I/O, just a map lookup on the writer's state).

## 6. `missing_chunks` Schema Update

The `missing_chunks` table (defined in [pq_files.md §14.3](pq_files.md#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes)) gains a `source_drive_id` column for drive copy provenance:

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Parent file |
| `chunk_index` | INTEGER | Position in file |
| `data_hash` | TEXT, NULL | `fd_`-prefixed hash — NULL until `file_chunks` manifest row arrives |
| `size` | INTEGER, NULL | Expected byte size — NULL until manifest row arrives |
| `peer_url` | TEXT, NULL | Network peer that advertised this chunk (for SyncSource). Set by `File.sync_after_persist` during Electric sync. |
| `source_drive_id` | TEXT, NULL | Drive ID of the replication source that has this chunk (for DriveCopySource). Set by the PG replica trigger listener (§5.0.2) when `missing_chunks` rows are created from replicated data. NULL for network-only chunks. |
| `attempts` | INTEGER, DEFAULT 0 | Retry bookkeeping — incremented by whichever source fails |
| `updated_at` | BIGINT | Last attempt or creation time (TimeKeeper) |
| | PK | `(file_id, chunk_index)` |

Indexes:

- `(attempts, updated_at)` WHERE `data_hash IS NOT NULL` — supports fallback poll selection for both DriveCopySource and SyncSource.
- `(peer_url)` WHERE `data_hash IS NOT NULL AND peer_url IS NOT NULL` — supports SyncSource reconnect sweep (§5.6.1).
- `(source_drive_id)` WHERE `data_hash IS NOT NULL AND source_drive_id IS NOT NULL` — supports DriveCopySource reconnect sweep (§5.6.2).

## 7. Interaction with PostgreSQL I/O

### 7.1 `ChunkStore.put` Write Flags

`ChunkStore.put` writes chunk bytes via `File.write(tmp_path, binary, [:raw, :sync])` + `File.rename`:

- **`:raw`** — bypasses the Erlang file server (a single process that serializes all non-raw file I/O across the VM). Without `:raw`, every 4 MB write queues behind all other file operations in the node — including cross-drive writes and PG's file I/O routed through the same file server. `:raw` talks directly to the OS, eliminating that bottleneck.
- **`:sync`** — flushes data to the storage device before returning. Without it, `File.write` returns when data reaches the OS page cache — on sudden power loss the `.tmp` file could be zero-length or partial, and `File.rename` would have already promoted it. `:sync` guarantees the bytes are on disk before the rename.

### 7.2 PG I/O Contention

ChunkWriter does not gate PostgreSQL writes — each drive's PG manages its own WAL/heap I/O. But serializing chunk writes to one-at-a-time per drive means PG never competes with multiple simultaneous 4 MB `File.write` calls on the same storage device. The net effect:

- **Upload path**: chunk FS write (ChunkWriter) happens first, then PG manifest insert (small row, ~5 KB). Sequential within one round — no overlap.
- **Drive copy / network sync**: chunk FS write (ChunkWriter), then PG `missing_chunks` delete (tiny write). Also sequential.
- **PG background**: WAL writes, autovacuum, checkpoint — run concurrently with ChunkWriter but face less contention since only one chunk write is in flight at any time on that drive.
- **Cross-drive reads**: DriveCopySource reads from *another* drive's ChunkStore — this does not contend with the local drive's writer or PG. Read I/O on the source drive is independent.

## 8. Replacing ElectricIngestThrottle

`ElectricIngestThrottle` (counting semaphore gating concurrent chunk ingest) becomes unnecessary. Its job — preventing concurrent large writes from starving the connection pool — is subsumed by ChunkWriter's single-writer model. The controller submits to the active drive's UploadSource and either queues or gets 429. Only one chunk writes to FS at a time per drive.

**Migration**: remove `ElectricIngestThrottle` and `ChatWeb.Plugs.ElectricIngestThrottle` after ChunkWriter is in place.

## 9. Lifecycle

The pipeline module code lives in Chat (ChunkStore, sources, writer are Chat modules). But the *supervisor* that starts them differs by drive type.

### 9.1 Internal Drive (SD)

The internal drive has no Platform boot sequence — Chat.Repo starts directly in `Chat.Application`. The internal drive's pipeline starts in **Chat's own supervision tree**, gated on Repo readiness:

```
Chat.Application supervisor
  └─ ... (Repo, PubSub, Endpoint, ...)
  └─ ChunkPipelineSupervisor (internal drive)
       ├─ ChunkWriter          (GenServer, permanent)
       ├─ ReplicationListener   (Postgrex.Notifications, permanent)
       ├─ UploadSource          (GenServer, permanent)
       ├─ DriveCopySource       (GenServer, permanent)
       └─ SyncSource            (GenServer, permanent)
```

On `:host` (development) this is the only pipeline — no Platform, no USB drives.

### 9.2 USB Drives

Each USB drive boots its pipeline group as part of Platform's drive boot sequence (after Repo + migrations are ready):

```
Platform.App.Drive.BootSupervisor (per USB drive)
  └─ ... (Healer, Mounter, PG, Repo, Migrations)
  └─ ChunkPipelineSupervisor
       ├─ ChunkWriter          (GenServer, permanent)
       ├─ ReplicationListener   (Postgrex.Notifications, permanent)
       ├─ UploadSource          (GenServer, permanent)
       ├─ DriveCopySource       (GenServer, permanent)
       └─ SyncSource            (GenServer, permanent)
```

### 9.3 Common

Process names are scoped per drive (e.g. via `{:via, Registry, {ChunkRegistry, {:writer, drive_id}}}`).

**Sources are always running.** They are event-driven sinks — idle until work arrives:

- **UploadSource**: receives chunks from `FileChunkController`. Idle when no uploads target this drive.
- **DriveCopySource**: activated by direct cast from ReplicationListener and drive mount events. Checks other mounted drives for bytes. Idle when no other drives are mounted or no casts arrive. Hourly fallback poll. Reconnect sweep on drive remount (§5.6.2).
- **SyncSource**: activated by direct cast from `sync_after_persist`. Fetches from network peers. Idle when no casts arrive. Hourly fallback poll. Reconnect sweep when a peer comes back online (§5.6.1).

Crash recovery: supervisor restarts the crashed process. ChunkWriter's `:queue` state is lost on restart — deferred callers receive `{:EXIT, ...}` and retry. If the in-flight write Task crashes, `handle_info({:DOWN, ref, ...})` clears `writing`, replies `{:error, :write_failed}` to the caller, and triggers the next round — the writer does not restart.

### 9.4 Main DB Switch and Upload Routing

The HTTP endpoint (`FileChunkController`) serves one active drive at a time — the "main" database. When Platform switches the main DB (via `Chat.Db.Switching`), the upload sink pointer must follow:

- **`FileChunkController`** resolves the active drive's `UploadSource` at request time (e.g. `UploadSource.submit(active_drive_id, chunk_data, meta)`).
- **Resolution**: a registry lookup or a module-level reference that `Chat.Db.Switching` updates on switch. No restart needed — the next upload simply routes to the new drive's UploadSource.
- **In-flight uploads**: an upload that started on the old drive completes on the old drive (its `GenServer.call` is already in that ChunkWriter's queue). Only new requests route to the new drive.

### 9.5 Drive Mount/Unmount

**Mount**: Platform starts the drive's `ChunkPipelineSupervisor`. DriveCopySources on *other* drives are notified of the new drive's `{repo, chunk_store_path}` (added to their source lists) and schedule a reconnect sweep (§5.6.2) — fires after 5 seconds if the drive is still mounted and the `:drive_copy` lane is idle.

**Unmount**: Platform stops the drive's pipeline group. DriveCopySources on other drives remove this drive from their source lists. In-flight `GenServer.call`s to the stopped ChunkWriter receive `{:EXIT, ...}` — sources retry or skip. Chunks whose `source_drive_id` pointed to the unmounted drive remain in `missing_chunks` — subsequent fetches fall back to a random available drive (§5.2) or wait for remount.

## 10. Observability

- **Starvation warnings**: log when a source's wait counter crosses 80% of its override threshold.
- **Source list changes**: log when DriveCopySource/SyncSource gain or lose a backend (drive mount/unmount, peer connect/disconnect).
- **Metrics** (if/when telemetry is added): rounds per source per drive, average wait per source, write latency distribution, cross-drive read count.

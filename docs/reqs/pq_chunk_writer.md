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

Each **source** is a permanent GenServer (always running, see §8) that acts as a sink — other code pushes chunks into the source, or the source polls for work. Sources submit to their drive's ChunkWriter.

### 2.1 Mechanism: GenServer + Deferred Reply + `:queue`

No external dependencies — the pipeline uses OTP/stdlib primitives:

- **Deferred reply**: sources call `GenServer.call(writer, {:submit, lane, chunk_data, meta})`. The writer does **not** reply immediately — it holds the caller's `from` reference (`{:noreply, state}` from `handle_call`) and buffers the request. The caller blocks until the writer selects and writes the chunk, then receives the result via `GenServer.reply(from, result)`.
- **`:queue`**: Erlang's double-ended queue (O(1) push/pop) backs each source lane's buffer inside ChunkWriter's state. Three queues: `:upload`, `:drive_copy`, `:network_sync`.
- **`handle_continue`**: after each write completes, the writer returns `{:noreply, state, {:continue, :next_round}}`. The `handle_continue(:next_round, state)` callback runs the selection algorithm and writes the next chunk — no `send(self(), ...)` needed, no extra message in the mailbox.

```elixir
# ChunkWriter state (conceptual)
%{
  drive_id: "sd",
  queues: %{
    upload:       :queue.new(),   # items: {from, chunk_data, meta}
    drive_copy:   :queue.new(),
    network_sync: :queue.new()
  },
  wait_counters: %{drive_copy: 0, network_sync: 0}
}
```

**Flow for one round**:

1. `handle_continue(:next_round, state)` — select source lane per §4
2. Pop head from selected lane's `:queue` → `{from, chunk_data, meta}`
3. `ChunkStore.put(meta.file_id, meta.chunk_index, chunk_data)` (synchronous FS write)
4. `GenServer.reply(from, result)` — unblocks the source's caller
5. Update wait counters per §4.3
6. Return `{:noreply, state, {:continue, :next_round}}` — loop continues
7. If all queues are empty → `{:noreply, state}` — loop pauses until next `handle_call` submit triggers `{:continue, :next_round}`

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

Each source is a permanent GenServer (one per drive) that acts as a **sink** — other code pushes chunks into it, or the source polls for work. The source is responsible for its own validation and post-write bookkeeping.

All three sources per drive are always running. They accept work when it arrives and are idle otherwise.

### 5.1 UploadSource (`:upload` lane)

- **Always running**: one per drive, started in the drive's pipeline supervisor.
- **Receives from**: `FileChunkController.create` — the controller validates signature/hash, then calls `UploadSource.submit(chunk_data, meta)` on the **active drive's** UploadSource (see §8.2 for main DB switching).
- **Submit flow**: `UploadSource` forwards to its drive's ChunkWriter via `GenServer.call` (deferred reply). The Plug process blocks until the chunk is written.
- **On reply (`:ok`)**: controller inserts `file_chunks` manifest row + `upload_chunks` bookkeeping row into PG, returns HTTP 200 to client.
- **Backpressure**: when 2 uploads are already queued in ChunkWriter, `UploadSource.submit` returns `{:busy, retry_after}` immediately — the controller responds with **429 + `Retry-After` header**. The client must not block indefinitely: its PoP challenge has a TTL, and a stalled request would expire it. This replaces `ElectricIngestThrottle` (§7).

### 5.2 DriveCopySource (`:drive_copy` lane)

- **Always running**: one per drive, started in the drive's pipeline supervisor. Idle until other drives are available.
- **Maintains**: a list of **other drives' `{repo, chunk_store_path}` pairs** — updated when drives mount/unmount. Does not include its own drive.
- **Polls**: periodically scans its own drive's `missing_chunks` table for work.

**Chunk selection**: selects missing chunks with **least `attempts`, randomized** among ties. Randomization prevents DriveCopySource and SyncSource from picking the same chunk on concurrent polls.

**`missing_chunks` provenance**: during drive-to-drive Electric sync, `missing_chunks` rows are populated with a `source_repo_path` field — the `{repo, chunk_store_path}` of the drive that advertised this chunk. This gives DriveCopySource a direct hint for where to read bytes.

**Fetch strategy**:

1. If the missing chunk has a `source_repo_path` → check that drive's ChunkStore first
2. If not found (or no hint) → try other known drives in order
3. If no drive has it → skip (leave for SyncSource to fetch over network)
4. If found but hash mismatch → increment `attempts`, skip

On successful write reply from ChunkWriter → delete `missing_chunks` row.

### 5.3 SyncSource (`:network_sync` lane)

- **Always running**: one per drive, replaces current `ChunkFetcher`'s direct `ChunkStore.put` calls.
- **Maintains**: a list of **known network peer URLs** — updated as peers connect/disconnect.
- **Polls**: periodically scans its own drive's `missing_chunks` table for work (existing ChunkFetcher logic).

**Chunk selection**: selects missing chunks with **least `attempts`, randomized** among ties — same strategy as DriveCopySource to spread work and avoid collisions.

**Fetch strategy**:

1. Try the chunk's `peer_url` from `missing_chunks` (the peer that advertised this file via Electric shape)
2. If that fails → try other known peer URLs
3. If all fail → increment `attempts`

- **Validation**: hash check against `data_hash` (unchanged from current `ChunkFetcher.admit_chunk`).
- **On reply (`:ok`)**: deletes `missing_chunks` row.

### 5.4 Collision Avoidance Between DriveCopySource and SyncSource

Both sources poll the same `missing_chunks` table on the same drive. To prevent both from fetching the same chunk simultaneously:

- **Randomized selection**: both select from the "least attempts" pool with random ordering — they are unlikely to pick the same chunk in the same poll cycle.
- **No hard lock**: if both do pick the same chunk, the second `ChunkStore.put` for an already-written chunk is idempotent (file exists, no-op or overwrite with identical bytes). The second `missing_chunks` delete is also idempotent (row already gone). Wasted work, not data corruption.
- **Natural separation**: DriveCopySource checks local drives first (fast) and skips chunks it can't find locally. SyncSource fetches over the network (slow). In practice, drive copy resolves first for chunks available locally.

## 6. `missing_chunks` Schema Update

The `missing_chunks` table (defined in [pq_files.md §14.3](pq_files.md#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes)) gains a `source_repo_path` column for drive copy provenance:

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Parent file |
| `chunk_index` | INTEGER | Position in file |
| `data_hash` | TEXT, NULL | `fd_`-prefixed hash — NULL until `file_chunks` manifest row arrives |
| `size` | INTEGER, NULL | Expected byte size — NULL until manifest row arrives |
| `peer_url` | TEXT, NULL | Network peer that advertised this chunk (for SyncSource) |
| `source_repo_path` | TEXT, NULL | `repo_module:chunk_store_path` of the drive that has this chunk (for DriveCopySource). Set during drive-to-drive Electric sync when the source drive is known. NULL for network-only chunks. |
| `attempts` | INTEGER, DEFAULT 0 | Retry bookkeeping — incremented by whichever source fails |
| `updated_at` | BIGINT | Last attempt or creation time (TimeKeeper) |
| | PK | `(file_id, chunk_index)` |

Index: `(attempts, updated_at)` WHERE `data_hash IS NOT NULL` — supports "least attempts, randomized" selection for both DriveCopySource and SyncSource.

## 7. Interaction with PostgreSQL I/O

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
       ├─ UploadSource          (GenServer, permanent)
       ├─ DriveCopySource       (GenServer, permanent)
       └─ SyncSource            (GenServer, permanent)
```

### 9.3 Common

Process names are scoped per drive (e.g. via `{:via, Registry, {ChunkRegistry, {:writer, drive_id}}}`).

**Sources are always running.** They are sinks — idle until work arrives:

- **UploadSource**: receives chunks from `FileChunkController`. Idle when no uploads target this drive.
- **DriveCopySource**: polls `missing_chunks`, checks other mounted drives. Idle when no other drives are mounted or no missing chunks have local sources.
- **SyncSource**: polls `missing_chunks`, fetches from network peers. Idle when no fetchable missing chunks exist.

Crash recovery: supervisor restarts the crashed process. ChunkWriter's `:queue` state is lost on restart — deferred callers receive `{:EXIT, ...}` and retry.

### 9.4 Main DB Switch and Upload Routing

The HTTP endpoint (`FileChunkController`) serves one active drive at a time — the "main" database. When Platform switches the main DB (via `Chat.Db.Switching`), the upload sink pointer must follow:

- **`FileChunkController`** resolves the active drive's `UploadSource` at request time (e.g. `UploadSource.submit(active_drive_id, chunk_data, meta)`).
- **Resolution**: a registry lookup or a module-level reference that `Chat.Db.Switching` updates on switch. No restart needed — the next upload simply routes to the new drive's UploadSource.
- **In-flight uploads**: an upload that started on the old drive completes on the old drive (its `GenServer.call` is already in that ChunkWriter's queue). Only new requests route to the new drive.

### 9.5 Drive Mount/Unmount

**Mount**: Platform starts the drive's `ChunkPipelineSupervisor`. DriveCopySources on *other* drives are notified of the new drive's `{repo, chunk_store_path}` (added to their source lists).

**Unmount**: Platform stops the drive's pipeline group. DriveCopySources on other drives remove this drive from their source lists. In-flight `GenServer.call`s to the stopped ChunkWriter receive `{:EXIT, ...}` — sources retry or skip.

## 10. Observability

- **Starvation warnings**: log when a source's wait counter crosses 80% of its override threshold.
- **Source list changes**: log when DriveCopySource/SyncSource gain or lose a backend (drive mount/unmount, peer connect/disconnect).
- **Metrics** (if/when telemetry is added): rounds per source per drive, average wait per source, write latency distribution, cross-drive read count.

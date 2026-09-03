# File Storage

Constraints, design, and schema for storing large files on BuckitUp platform devices. **Chunk bytes live on the filesystem as raw encrypted bytes** — one file per chunk. Manifests and bookkeeping live in PostgreSQL, with the manifest tables (`files`, `file_chunks`) in the Electric publication for device-to-device sync. See [Chunk Pipeline](../pq_chunk_writer.md) for the per-drive admission pipeline and [PostgreSQL Constraints](../pg_constraints.md) for TOAST/WAL/VACUUM background.

> **History**: chunk blobs originally lived in PostgreSQL as base64 `BYTEA`. That design was replaced (protocol v2) by filesystem storage of raw bytes — base64 left the chunk protocol end-to-end. See [§14 Implementation History](#14-implementation-history) for what changed and why.

## 1. Tables

### 1.1 `files` (Electric-synced)

One row per completed file. Created only after all chunks are uploaded and verified. The trust anchor — a receiving device uses this row to decide whether to accept `file_chunks`.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, PK | `"f_" + UUIDv7` (32 hex chars, dashes stripped). CHECK `^f_[a-f0-9]{32}$` |
| `uploader_hash` | TEXT, NOT NULL | FK → `user_cards` |
| `total_size` | BIGINT, NOT NULL | Plaintext file size in bytes |
| `chunk_size` | INTEGER, NOT NULL, DEFAULT 4194304 | Bytes per chunk (4 MB) |
| `chunk_count` | INTEGER, NOT NULL | Total number of chunks |
| `chunk_sign_hashes` | BYTEA[], NOT NULL | Array of `SHA3-512(chunk.sign_b64)` for each chunk, ordered by `chunk_index` |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `deleted_flag` | BOOLEAN, NOT NULL, DEFAULT false | Soft delete |
| `sign_b64` | BYTEA, NOT NULL | ML-DSA-87 signature over all other fields |

Schema: [`Chat.Data.Schemas.File`](../../../lib/chat/data/schemas/file.ex). Custom types: [`FileId`](../../../lib/chat/data/types/file_id.ex), [`UserHash`](../../../lib/chat/data/types/user_hash.ex).

**Verification**: for each chunk, compute `SHA3-512(chunk.sign_b64)` and compare against `chunk_sign_hashes[chunk_index]`. Since each chunk's `sign_b64` covers the chunk's `data_hash` (SHA3-512 over the raw encrypted bytes), this transitively binds chunk data integrity to the `files` manifest signature.

### 1.2 `file_chunks` (Electric-synced, manifest only)

One row per chunk — **metadata only, no blob**. The chunk's encrypted bytes live on the filesystem in `ChunkStore` (§9.1); this row carries the hash that binds them. Rows are ~5 KB (dominated by the ML-DSA-87 signature), so the table stays in the Electric publication cheaply.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, NOT NULL | Parent file reference (PK part) |
| `chunk_index` | INTEGER, NOT NULL | 0-based position (PK part) |
| `data_hash` | TEXT, NOT NULL | `"fd_"` + lowercase hex `SHA3-512(raw encrypted bytes)`. CHECK `^fd_[a-f0-9]{128}$` |
| `size` | INTEGER, NOT NULL | Encrypted chunk byte size |
| `uploader_hash` | TEXT, NOT NULL | FK → `user_cards` |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `sign_b64` | BYTEA, NOT NULL | Signature over `(file_id, chunk_index, data_hash, size, uploader_hash, owner_timestamp)` |
| | PK | `(file_id, chunk_index)` |

Schema: [`Chat.Data.Schemas.FileChunk`](../../../lib/chat/data/schemas/file_chunk.ex). `data_hash` uses Ecto type [`Chat.Data.Types.FileChunkDataHash`](../../../lib/chat/data/types/file_chunk_data_hash.ex) — the single canonical representation used everywhere: stored in this row, carried on the wire (`x-data-hash` header), and included in the signed payload. There is exactly one form to hash, sign, store, and serve; no re-encoding. `files.chunk_sign_hashes[chunk_index]` binds to `SHA3-512(sign_b64)`, which in turn covers `data_hash`, transitively binding the on-disk bytes to the manifest signature.

**Sync filtering**: a `file_chunks` row is accepted from a peer only when a matching `files` row exists, is not deleted, and its `uploader_hash` matches the chunk's. Chunk manifest rows that arrive before their `files` parent are deferred (not dropped). See §5.

Sync filtering is implemented in [`Chat.Data.Shapes.FileChunk.sync_validate_parent/2`](../../../lib/chat/data/shapes/file_chunk.ex).

### 1.3 `upload_chunks` (local only, NOT Electric-synced)

Tracks uploaded chunks before the signed `files` manifest arrives. Populated as a side effect of chunk upload — the device writes a bookkeeping row with server-set `updated_at` from TimeKeeper. Provides ownership tracking, upload resume, and unsigned-data accounting.

| Column | Type | Description                      |
|---|---|----------------------------------|
| `file_id` | TEXT | Client-provided `"f_" + UUIDv7` |
| `chunk_index` | INTEGER | Position in file                 |
| `chunk_sign_hash` | BYTEA, NOT NULL | `SHA3-512(chunk.sign_b64)` — matches `files.chunk_sign_hashes` for GC verification |
| `uploader_hash` | TEXT, NOT NULL | Who uploaded this chunk          |
| `size` | INTEGER, NOT NULL | Blob byte size                   |
| `updated_at` | BIGINT, NOT NULL | Unix seconds (from TimeKeeper)   |
| | PK | `(file_id, chunk_index)`         |

Schema: [`Chat.Data.Schemas.UploadChunk`](../../../lib/chat/data/schemas/upload_chunk.ex).

Indexes: `uploader_hash` (budget queries), `updated_at` (GC queries).

**Queries this table supports**:
- **Unsigned budget**: `SUM(size) WHERE uploader_hash = ? AND file_id NOT IN (SELECT file_id FROM files)` — uncommitted bytes per user
- **GC**: `WHERE updated_at < threshold AND file_id NOT IN (SELECT file_id FROM files)` — delete stale rows + orphan chunks (§8)

**Not used for resume**, despite the name: a row here is deleted once the file's manifest commits (§4), so a resume query against it would wrongly report zero progress for an already-finished upload. The client-facing resume query reads `file_chunks` instead — see §4.1.

### 1.4 `missing_chunks` (local only, NOT Electric-synced)

Tracks chunks whose bytes are not yet in the local `ChunkStore`. It is the queue that drives device-to-device sync: rows are created when a manifest arrives from another device and deleted once the bytes are fetched and verified.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Parent file (PK part) |
| `chunk_index` | INTEGER | Position in file (PK part) |
| `data_hash` | TEXT, NULL | `"fd_"` hash — NULL = **placeholder** (manifest metadata not yet arrived); non-NULL = **fetchable** |
| `size` | INTEGER, NULL | Expected byte size — NULL until the `file_chunks` manifest row arrives |
| `peer_url` | TEXT, NULL | Network peer that advertised the chunk (`SyncSource` hint) |
| `source_drive_id` | TEXT, NULL | PG `system_identifier` of the replication-source drive (`DriveCopySource` hint) |
| `attempts` | INTEGER, NOT NULL, DEFAULT 0 | Retry bookkeeping |
| `updated_at` | BIGINT, NOT NULL | Last attempt or creation time (TimeKeeper) |
| | PK | `(file_id, chunk_index)` |

Schema: [`Chat.Data.Schemas.MissingChunk`](../../../lib/chat/data/schemas/missing_chunk.ex).

**Two-stage population** (avoids a false-availability window — a file must never look complete before its chunks are even tracked):

1. **`files` manifest arrives from a peer** → pre-seed `chunk_count` placeholder rows (indices `0..chunk_count-1`, `data_hash = NULL`). The file has a non-zero missing count from the moment its manifest lands.
2. **`file_chunks` manifest row arrives** → fill `data_hash` + `size` on the matching row, making it fetchable.

The uploading device never populates this table — it wrote the bytes to `ChunkStore` during upload, so all chunks are present locally when it commits the manifest.

One table, three consumers: the **fetch queue** (rows where `data_hash IS NOT NULL`), the **UI signal** (per-file count vs `chunk_count`), and the **availability check** (`files` present AND zero `missing_chunks` rows). It is rebuildable at any time by anti-joining expected indices against the store ([`MissingChunksBackfill`](../../../lib/chat/data/file/missing_chunks_backfill.ex)), so it is corruption-safe.

Indexes (from migrations [`20260613120002`](../../../priv/repo/migrations/20260613120002_create_missing_chunks.exs) and [`20260627120000`](../../../priv/repo/migrations/20260627120000_add_source_drive_id_to_missing_chunks.exs)):
- `missing_chunks_fetchable_idx` on `(attempts, updated_at) WHERE data_hash IS NOT NULL`
- `missing_chunks_peer_url_fetchable_idx` on `(peer_url) WHERE data_hash IS NOT NULL AND peer_url IS NOT NULL`
- `missing_chunks_source_drive_id_fetchable_idx` on `(source_drive_id) WHERE data_hash IS NOT NULL AND source_drive_id IS NOT NULL`

See [pq_chunk_writer.md §4.1](../pq_chunk_writer.md) for how the fetch sources consume them.

## 2. Chunk Encryption

All encryption/decryption happens client-side (browser, Web Crypto API).

- **Algorithm**: AES-256-GCM
- **Key**: `enc_secret` — random 32 bytes, unique per file
- **Nonce**: 12 random bytes (`crypto.getRandomValues`), prepended to ciphertext
- **Auth tag**: 16 bytes, appended to ciphertext (standard GCM output)
- **Chunk wire format**: `nonce(12) || ciphertext || tag(16)`

```
nonce = crypto.getRandomValues(12)
encrypted_chunk = nonce || AES-256-GCM(enc_secret, nonce, plaintext_chunk)
```

Nonce safety: `enc_secret` is unique per file (no reuse across files), random 96-bit nonces have negligible collision probability at file-scale chunk counts (birthday bound ~2^32 encryptions per key ≈ 16 TB at 4 MB chunks).

The device stores and serves the raw encrypted bytes (including the prepended nonce) and never sees plaintext.

## 3. Content Type

The `"file"` content type and its positional array schema are defined in [07_content_polymorphism.md § `"file"`](../../invariants/07_content_polymorphism.md#file).

## 4. Upload Protocol

Chunks upload via a **dedicated raw binary endpoint**; the `files` manifest uses JSON ingest.

**Chunk upload** — `PUT /electric/v1/file_chunk/:file_id/:chunk_index`:

Implementation: [`ChatWeb.FileChunkController.create/2`](../../../lib/chat_web/controllers/file_chunk_controller.ex).

- Raw encrypted bytes in the body; metadata + signature in headers: `x-data-hash` (`fd_`-prefixed), `x-size`, `x-uploader-hash`, `x-owner-timestamp`, `x-signature`.
- The server verifies the ML-DSA-87 signature (against the uploader's `sign_pkey` from `user_cards`) and the deleted-file / uploader-match checks **before reading the body** — an unknown user or bad signature costs one verify, not a 4 MB read.
- Then: free-space check → read body → hash the body and compare to the signed `data_hash` → submit to [`ChunkWriter`](../../../lib/chat/data/file/chunk_writer.ex) via [`UploadSource`](../../../lib/chat/data/file/upload_source.ex) (`:upload` lane) → insert `file_chunks` row → insert `upload_chunks` row (separate idempotent inserts with `on_conflict: :nothing`).
- **No challenge/PoP** on this endpoint — the chunk signature binds the uploader key to the exact bytes, position, and `owner_timestamp`, which is strictly stronger than the ingest challenge. A replayed PUT is an idempotent no-op (same PK, hash-identical body).
- Statuses: **200** ok; **429** upload lane busy (`Retry-After`); **401** bad signature; **410** file deleted; **403** uploader mismatch; **422** hash/size mismatch; **413** disk full / body too large; **400** missing headers; **500** chunk write failed; **503** storage not ready / writer unavailable.

**Manifest commit** — `POST /electric/v1/ingest` (JSON): after all chunks are on the device, the client builds the `files` row with `chunk_sign_hashes` (computed locally from its own `sign_b64` values), signs it, and ingests it. The device verifies the manifest signature (via [`Chat.Data.File.Validation.file_pre_apply_insert/3`](../../../lib/chat/data/file/validation.ex)), that all `chunk_count` chunks are present, and that each `chunk_sign_hashes[i]` matches the stored chunk's `SHA3-512(sign_b64)`, then syncs the ChunkStore directory and deletes the `upload_chunks` rows.

```
Client                                    Device
  │                                          │
  │  encrypt chunk i client-side             │
  │  sign (file_id, i, data_hash=            │
  │    SHA3-512(raw), size, uploader,        │
  │    owner_timestamp)                      │
  │─ PUT /electric/v1/file_chunk/:id/:i ────>│  headers: x-data-hash, x-size,
  │    body: raw encrypted bytes             │    x-uploader-hash, x-owner-timestamp,
  │                                          │    x-signature
  │                                          │  verify signature (before body read)
  │                                          │  read body → hash → compare data_hash
  │                                          │  ChunkWriter ← UploadSource (raw bytes → FS)
  │                                          │  insert file_chunks + upload_chunks
  │<─ 200 | 429 | 401 | 410 | 413 | 500 ────│
  │─ ... progressive encrypt + upload ...    │
  │                                          │
  │  resume: shape read on file_chunks       │
  │  by file_id → existing chunk_indexes     │
  │  (§4.1)                                  │
  │                                          │
  │  all chunks uploaded                     │
  │  build + sign files manifest with        │
  │    chunk_sign_hashes array               │
  │─ POST /electric/v1/ingest (JSON) ───────>│  files insert
  │                                          │  verify: sign_b64; all chunks present;
  │                                          │    each chunk_sign_hash matches
  │                                          │  sync ChunkStore dir
  │                                          │  delete upload_chunks for file_id
  │<─ 200 {txid} ────────────────────────────│  committed to Electric
```

### 4.1 Resume

**Client-side persistence (prerequisite)**: the device has no "list my in-progress uploads" endpoint — resume is entirely client-initiated, keyed by `file_id`. Before the first chunk `PUT`, the client must durably persist, per started upload: `file_id`, `enc_secret` (§2), `chunk_size`, and `total_size`/`chunk_count`. `file_id` alone is not sufficient — `enc_secret` is a single random value per file (§2), so a resumed session that generated a fresh secret couldn't produce chunks decryptable together with the ones already uploaded under the original secret, even though the server-side chunks themselves are intact. The client removes the record once the manifest commits (§4) or the upload is abandoned.

An interrupted upload resumes with the persisted `file_id`: the client diffs `0..chunk_count-1` against the chunk indexes the device already has, then re-`PUT`s just the missing ones (re-encrypted from the source file with the persisted `enc_secret`).

**Discovery: direct shape read** — `file_chunks` rows are the device's evidence that a chunk was received and hash-verified (§1.2), and the table is already exposed via the unauthenticated Electric shape endpoint (§5):

```
GET /electric/v1/shapes?table=file_chunks&where=file_id='<file_id>'
```

This is safe without proving anything about `uploader_hash`: before a file's manifest commits, `file_chunks` rows for a given `file_id` exist only on the device the client uploaded directly to — a peer device defers/rejects incoming `file_chunks` rows until it has the matching `files` parent (§1.2), so no other device could have replicated them yet. `file_id` is therefore already a sufficient capability to read its own chunk list, the same way it's already sufficient for downloads (§6) — no separate proof of identity is needed.

Client re-`PUT`s the chunk indexes absent from the response (§4 chunk upload).

> There was previously a `POST /upload_chunks` (PoP-gated) alternative for clients that didn't want to implement the Electric shape protocol. It has been removed — the shape read above is the only supported resume path now. `uploader_hash`-scoped querying (enumerating a user's uploads without a known `file_id`) is intentionally not offered.

**Why `file_chunks`, not `upload_chunks`, despite the name?** `upload_chunks` rows are written alongside `file_chunks` on every chunk `PUT` (§4) but are deleted once the manifest commits (§4, §8) — querying it for an upload that already finished would wrongly report zero progress. `file_chunks` is written first, is Electric-synced (so it reflects chunks accepted on any app node, not just the one the resume request happens to hit), and persists until the file itself is deleted (§7). It is a superset of `upload_chunks` at every point in an upload's lifecycle.

## 5. Sync Protocol

Manifest rows sync via Electric / logical replication; **bytes never travel through Electric** — they are fetched separately and admitted only after a hash check.

Manifest sync (`files`, `file_chunks`) flows through Electric shapes, filtered as in §1.2: the parent `files` row must be present, not deleted, and `uploader_hash` must match; orphan chunk rows are deferred until their parent arrives. Shape behaviour implementations: [`Chat.Data.Shapes.File`](../../../lib/chat/data/shapes/file.ex) and [`Chat.Data.Shapes.FileChunk`](../../../lib/chat/data/shapes/file_chunk.ex).

Byte acquisition follows two paths (full pipeline in [pq_chunk_writer.md](../pq_chunk_writer.md)):

1. **Network sync ([`SyncSource`](../../../lib/chat/data/file/sync_source.ex))** — when a `files` manifest arrives from a peer, [`Shapes.File.sync_after_persist/3`](../../../lib/chat/data/shapes/file.ex) pre-seeds `missing_chunks` placeholders (§1.4). As each `file_chunks` manifest row arrives, [`Shapes.FileChunk.sync_after_persist/3`](../../../lib/chat/data/shapes/file_chunk.ex) fills the matching row and notifies `SyncSource`; `SyncSource` issues `GET /electric/v1/file_chunk/:file_id/:chunk_index` to the peer, verifies the body against `data_hash`, admits it to `ChunkStore` via `ChunkWriter`, and deletes the `missing_chunks` row.
2. **Drive-to-drive copy ([`DriveCopySource`](../../../lib/chat/data/file/drive_copy_source.ex))** — PG logical replication delivers manifest rows between per-drive databases; a replica trigger fires `pg_notify`, [`ReplicationListener`](../../../lib/chat/data/file/replication_listener.ex) fills `missing_chunks` (stamping `source_drive_id`), and `DriveCopySource` reads the bytes directly from the other drive's on-disk `ChunkStore`.

**Availability**: a file is available once its `files` manifest is present AND it has zero `missing_chunks` rows. The per-file `missing_chunks` count (against `chunk_count`) is the honest "X of Y synced" signal at every stage — including the placeholder stage, where metadata has not yet arrived.

**Receiver integrity** (any byte source): the byte channel is untrusted by design — integrity is enforced at admission, not in transport. `ChunkStore` admits bytes only through a hash-checked write: unverified bytes exist only as `*.tmp`, renamed into place after `SHA3-512(bytes)` matches `data_hash`. **Presence in the store implies verified.** The trust chain: `user_cards.sign_pkey` → `files.sign_b64` → `chunk_sign_hashes[]` → a chunk's `sign_b64` → its `data_hash` → the bytes. A chunk file without a verified manifest row is an orphan (never served, reclaimed by GC). Behind the device sits the client's own end-to-end check — it re-verifies `data_hash` on download and AES-GCM authentication fails on any corruption — so device-side checks exist for self-healing (bitrot → delete → re-fetch), not as the client's last line of defense.

## 6. Download Protocol

### 6.1 Direct Chunk Endpoint

```
GET /electric/v1/file_chunk/:file_id/:chunk_index
```

Returns the raw encrypted chunk bytes as `application/octet-stream`, read from `ChunkStore` on the filesystem. Response header `x-chunk-size` carries the chunk's `size` value.

**Implementation**: [`ChatWeb.FileChunkController.show/2`](../../../lib/chat_web/controllers/file_chunk_controller.ex) → [`Chat.Data.File.ChunkStore.fetch/2`](../../../lib/chat/data/file/chunk_store.ex) (single on-disk file read; the chunk metadata row supplies `size`).

**Why not Electric shapes?** Each unique `(table, where)` combination creates a persistent Electric shape: a Consumer GenServer, a PG snapshot transaction, disk-backed shape log, and ongoing WAL filtering. Fetching N chunks via shapes creates N long-lived server-side resources for what is a simple point read. The direct endpoint performs one file read with no persistent overhead. This matters especially for video streaming (see [pq_video_streaming.md §6](../pq_video_streaming.md#6-chunk-fetch-strategy)), where seeking triggers many single-chunk fetches.

### 6.2 Chunk Status Endpoint

```
GET /electric/v1/file_chunk_status?file_ids=<id1>,<id2>,...
```

Returns per-file `on_disk` count (from `ChunkStore`) and `missing` count (from `missing_chunks`). Used by the UI to show sync progress without polling individual chunk rows.

**Implementation**: [`ChatWeb.FileChunkStatusController.index/2`](../../../lib/chat_web/controllers/file_chunk_status_controller.ex).

### 6.3 Download Flow

```
Client                              Device
  │                                    │
  │─── GET /electric/v1/shapes ───────>│  fetch files manifest
  │    ?table=files&where=file_id=?    │  (one Electric shape, small row)
  │<── {chunk_count, chunk_sign_hashes}│
  │                                    │
  │  for i in 0..chunk_count-1:        │
  │─── GET /electric/v1/file_chunk ───>│  direct endpoint, raw binary
  │       /:file_id/:i                 │  from ChunkStore
  │<── application/octet-stream ───────│  x-chunk-size header
  │  verify SHA3-512(bytes)==data_hash │
  │  decrypt with AES-256-GCM          │
  │  append to output                  │
```

The `files` manifest is fetched once via an Electric shape (small row, acceptable overhead). Individual chunks use the direct endpoint — no shape creation per chunk.

## 7. Deletion Protocol

To delete a file, the client updates the `files` row:
1. Set `deleted_flag = true`
2. Set `chunk_sign_hashes = '{}'` (empty array)
3. Re-sign the row

Emptying `chunk_sign_hashes` ensures receiving devices cannot verify any chunks for this file, so the sync protocol (§5) will skip them. The signed update propagates via Electric to all devices, where GC (§8) reclaims the chunk bytes and bookkeeping.

## 8. Garbage Collection

[`Chat.Data.File.GC`](../../../lib/chat/data/file/gc.ex) runs hourly. Two triggers reclaim chunk bytes and bookkeeping:

1. **Deleted files** (`files.deleted_flag = true`): delete the `file_chunks` rows (in batches of 50), the `missing_chunks` rows, and the file's `ChunkStore` directory. The `files` row is retained as a deletion tombstone.
2. **Stale uploads** (`upload_chunks.updated_at` older than 48 h AND `file_id NOT IN files` — upload never completed): delete `upload_chunks`, orphan `file_chunks` (batched), `missing_chunks`, and the `ChunkStore` directory.

Separately, [`TmpSweeper`](../../../lib/chat/data/file/tmp_sweeper.ex) (per drive, hourly, `gen_statem`) removes `*.tmp` files older than 1 h — residue from writes interrupted by a crash.

## 9. Storage Layout

### 9.1 ChunkStore (filesystem)

[`Chat.Data.File.ChunkStore`](../../../lib/chat/data/file/chunk_store.ex) — raw encrypted bytes, one file per chunk:

```
<files_base_dir>/pq_files/<last-2-hex-of-file_id>/<file_id>/<10-digit-zero-padded-chunk_index>
```

- **Sharding**: the last two hex chars of `file_id` (from UUIDv7's random tail → uniform 256-way split) keep per-directory entry counts low for FAT/exFAT drives. The front of the ID is not used — it is the `f_` prefix followed by the UUIDv7 timestamp, whose leading hex chars are effectively constant.
- **Writes**: temp file + `rename`. Sync (`datasync`) is deferred to manifest commit time ([`Validation.file_pre_apply_insert`](../../../lib/chat/data/file/validation.ex) calls `ChunkStore.sync_dir/1`), not per-chunk — a crash leaves at most a stale `*.tmp`, never a torn chunk.
- **Per drive**: each storage device (SD, USB) has its own `ChunkStore` path and its own `missing_chunks` table; a drive is identified by its PostgreSQL `system_identifier`.
- API: `put/4`, `fetch/2`, `count_on_disk/1`, `delete_file/1`, `sweep_tmp_files/1`, `available_space/0`, `sync_dir/1`, `file_dir/1` (all accept an optional `base_dir` override, raising max arity by 1).

### 9.2 PostgreSQL

PG now stores only manifest metadata (~5 KB rows), not chunk bytes. The v1 blob-specific accommodations have been reverted:

- `STORAGE EXTERNAL` on `data_b64` — the column was dropped.
- Aggressive autovacuum overrides on `file_chunks` — reset to defaults (migration `20260613120001`).
- `max_wal_size` — back to 256 MB (`platform/lib/platform/tools/postgres/lifecycle.ex`).
- `ElectricIngestThrottle` — removed; the single-writer `ChunkWriter` (per drive) subsumes it.

Multi-MB blob INSERTs no longer hit WAL or logical replication — only small manifest rows do. `wal_compression` is irrelevant to chunks now, and the base64-canonicalization hazard is gone (one raw representation everywhere).

## 10. Hardware Constraints

### 10.1 Device Memory
- **Total RAM**: 4 GB, shared between PostgreSQL and the Elixir/Erlang application.
- The device does not encrypt/decrypt — it stores and serves opaque encrypted chunks. At 4 MB per chunk it needs ~4–8 MB to buffer a chunk during ingest, well within budget. Uploads are serialized per drive (`ChunkWriter`, one write in flight), bounding peak buffering.

### 10.2 Storage
- Chunk bytes live on the FS drive (SD/USB) under `ChunkStore`, sharded two levels deep. The shard keeps per-directory entry counts within FAT/exFAT limits — FAT semantics (weak rename atomicity, no dir fsync) are an accepted risk class, equivalent to the platform's `fsync=off` PostgreSQL.
- PostgreSQL holds only manifest metadata (TOAST no longer relevant for chunks).

## 11. Cryptographic Constraints

### 11.1 AES-256-GCM
- **Per-key data limit**: ~64 GB (2^32 blocks x 16 bytes)
- **No streaming mode**: GCM requires the entire plaintext in memory for encryption/decryption (authentication tag is computed over the full message)
- **Nonce**: 12 bytes (96 bits), must be unique per encryption under the same key
- **Auth tag**: 16 bytes per chunk

### 11.2 Nonce Exhaustion
- With **random 96-bit nonces**, collision probability becomes meaningful after ~2^48 encryptions per key (birthday bound on 96-bit space)
- At 4 MB chunks, practical file sizes (even 1 TB = 256K chunks) are far below the collision threshold
- Each `enc_secret` is unique per file, so nonce reuse across files is impossible

### 11.3 Client-Side Encryption
- All encryption/decryption happens **exclusively in the browser** (Web Crypto API / SubtleCrypto)
- The device (server) never sees plaintext — it stores, serves, and transfers opaque encrypted chunks
- At 4 MB chunks, browser needs ~10 MB per encryption (plaintext + ciphertext + overhead) — safe on all modern devices including mobile
- SubtleCrypto does not natively support streaming AES-GCM

## 12. Chunk Size Decision

### 12.1 Chosen Size: 4 MB

**Rationale**:
- Fits comfortably in browser memory for AES-GCM (~10 MB working set per chunk)
- 4x fewer rows than 1 MB — reduces manifest row count and `chunk_sign_hashes` array size
- Allows SHA3-512 for hashing (64 bytes per entry) while keeping manifest size reasonable: 1 TB file = 256K entries × 64 bytes = 16 MB
- Unifies hashing with existing `EnigmaPq.hash/1` (SHA3-512) — no separate hash function needed
- Device only buffers opaque encrypted blobs during transfer — no crypto overhead on device
- Acceptable resumability on LAN/WiFi connections (4 MB retry on failure)

### 12.2 Trade-offs Considered

| Alternative | Pro | Con |
|---|---|---|
| 1 MB | Fine-grained resume | 4x more manifest rows; forces SHA3-256 to keep manifest size down; needs separate hash function |
| 4 MB (chosen) | Balanced — enables SHA3-512, reasonable row count | 4 MB retry on resume |
| 8-16 MB | Smallest manifests | Memory pressure on low-end mobile; poor resumability |

## 13. Resolved Questions

- **Unsigned budget**: no explicit budget — GC (§8, trigger 2) clears stale unsigned data after 2 days.
- **Max file size**: 1 TB hard cap.
- **Partial file availability**: client's call — the client decides when to start downloading/decrypting. For videos, streaming before all chunks are synced makes sense.
- **Hash algorithm**: SHA3-512 over the **raw encrypted bytes** — matches `EnigmaPq.hash/1`, same Keccak family as ML-DSA-87's internal SHAKE-256. 64-byte output is acceptable at 4 MB chunk size (1 TB = 256K entries = 16 MB manifest).
- **Chunk byte acquisition during sync**: manifest rows sync via Electric; bytes are fetched out-of-band — over HTTP from a peer (`SyncSource`) or copied drive-to-drive from another mounted drive's `ChunkStore` (`DriveCopySource`) — tracked by the `missing_chunks` queue (§1.4).
- **Peer/drive addressing**: `missing_chunks.peer_url` / `source_drive_id` hint where a chunk lives; `SyncSource` falls back to trying every connected peer, `DriveCopySource` to any mounted drive that has it.
- **WAL sizing**: historical — with chunk bytes off PostgreSQL, `max_wal_size` reverted to 256 MB.

## 14. Implementation History

v1 stored chunk blobs in PostgreSQL as base64 `BYTEA`. Measured on RPi4, each 4 MiB base64 chunk cost ~5.3 MB heap+TOAST + ~5.3 MB WAL (~2.7x write amplification) at ~3.6 MB/s — and since the platform runs PG with `fsync=off`/`synchronous_commit=off`/`full_page_writes=off` (`platform/lib/platform/tools/postgres/lifecycle.ex`), that WAL bought no power-loss durability, only replication transport. `wal_compression` was a no-op on high-entropy encrypted payloads (measured 1:1). v2 moved chunk bytes to the filesystem as raw bytes, dropping base64 end-to-end and leaving only manifests in PG/Electric.

Benchmark (50 × 4 MiB incompressible inserts through `Chat.Repo`, `STORAGE EXTERNAL`, one commit per insert):

| Metric | Logged table (v1) | Unlogged table |
|---|---|---|
| Time per 4 MiB insert | 1100 ms (~3.6 MB/s) | 754 ms (~5.4 MB/s) |
| WAL generated | 214 MB per 208 MB data (1:1) | ~0 |

Realized gains per 100 MB upload (26 chunks):

| | v1 (PG + base64) | v2 (FS, raw) |
|---|---|---|
| Bytes on the wire (up + down) | ~133 MB each way | 100 MB each way |
| Device bytes written | ~270 MB (heap+TOAST + WAL) | 100 MB (raw file, written once) |
| WAL burst | ~133 MB → checkpoint storm | ~130 KB (manifest rows) |
| Dead-tuple bloat per deleted file | ~133 MB TOAST awaiting vacuum | `rm -r` of one directory |

**Migrations** (PoC cutover — no backfill; v1 signatures hash base64 and cannot be re-signed server-side, so legacy chunk rows were truncated):

- [`20260512080650_create_files`](../../../priv/repo/migrations/20260512080650_create_files.exs)
- [`20260512080651_create_file_chunks`](../../../priv/repo/migrations/20260512080651_create_file_chunks.exs)
- [`20260512080652_create_upload_chunks`](../../../priv/repo/migrations/20260512080652_create_upload_chunks.exs)
- [`20260512080653_add_files_and_file_chunks_to_electric_publication`](../../../priv/repo/migrations/20260512080653_add_files_and_file_chunks_to_electric_publication.exs)
- [`20260613120000_v2_file_chunks_to_filesystem`](../../../priv/repo/migrations/20260613120000_v2_file_chunks_to_filesystem.exs) — add `data_hash`, drop `data_b64`, `TRUNCATE files, file_chunks, upload_chunks`
- [`20260613120001_file_chunks_reset_autovacuum`](../../../priv/repo/migrations/20260613120001_file_chunks_reset_autovacuum.exs) — reset autovacuum overrides to defaults
- [`20260613120002_create_missing_chunks`](../../../priv/repo/migrations/20260613120002_create_missing_chunks.exs)
- [`20260627120000_add_source_drive_id_to_missing_chunks`](../../../priv/repo/migrations/20260627120000_add_source_drive_id_to_missing_chunks.exs) — add `source_drive_id`, make `peer_url` nullable, add partial indexes
- [`20260627120001_create_replica_triggers`](../../../priv/repo/migrations/20260627120001_create_replica_triggers.exs) — `pg_notify` on `files`/`file_chunks` replica inserts (drives drive-copy sync)
- [`20260807100000_drop_duplicate_missing_chunks_index`](../../../priv/repo/migrations/20260807100000_drop_duplicate_missing_chunks_index.exs) — drop redundant `missing_chunks_attempts_updated_at_index`

**Pipeline**: the per-drive chunk admission pipeline — a serialized [`ChunkWriter`](../../../lib/chat/data/file/chunk_writer.ex) fed by [`UploadSource`](../../../lib/chat/data/file/upload_source.ex), [`SyncSource`](../../../lib/chat/data/file/sync_source.ex), and [`DriveCopySource`](../../../lib/chat/data/file/drive_copy_source.ex) over a shared [`ChunkSource`](../../../lib/chat/data/file/chunk_source.ex) behaviour — is documented in [pq_chunk_writer.md](../pq_chunk_writer.md). It replaced the single `ChunkFetcher` worker sketched in early drafts (never shipped) and the removed `ElectricIngestThrottle`. The pipeline is supervised by [`ChunkPipelineSupervisor`](../../../lib/chat/data/file/chunk_pipeline_supervisor.ex), which also starts [`ReplicationListener`](../../../lib/chat/data/file/replication_listener.ex), [`TmpSweeper`](../../../lib/chat/data/file/tmp_sweeper.ex), [`MissingChunksBackfill`](../../../lib/chat/data/file/missing_chunks_backfill.ex), and [`DriveAnnouncer`](../../../lib/chat/data/file/drive_announcer.ex).

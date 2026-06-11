# File Storage

Constraints, design, and schema for storing large files on BuckitUp platform devices. All chunk data lives in PostgreSQL — no filesystem storage. See also [PostgreSQL Constraints](pg_constraints.md) for TOAST, WAL amplification, and VACUUM considerations affecting large-value columns.

> **Migration planned (protocol v2)**: chunk blobs are moving out of PostgreSQL into filesystem storage as raw bytes — base64 leaves the chunk protocol entirely; manifests stay in PG/Electric. See [§14 Migration Plan](#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes). Sections 1-13 describe the current (all-in-PG, base64) design.

## 1. Tables

### 1.1 `files` (Electric-synced)

One row per completed file. Created only after all chunks are uploaded and verified. The trust anchor — a receiving device uses this row to decide whether to accept `file_chunks`.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, PK | `"f_" + UUIDv7` |
| `uploader_hash` | TEXT, NOT NULL | FK-like → user_cards |
| `total_size` | BIGINT, NOT NULL | Plaintext file size in bytes |
| `chunk_size` | INTEGER, NOT NULL, DEFAULT 4194304 | Bytes per chunk (4 MB) |
| `chunk_count` | INTEGER, NOT NULL | Total number of chunks |
| `chunk_sign_hashes` | BYTEA[], NOT NULL | Array of `SHA3-512(chunk.sign_b64)` for each chunk, ordered by `chunk_index` |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `deleted_flag` | BOOLEAN, NOT NULL, DEFAULT false | Soft delete |
| `sign_b64` | BYTEA, NOT NULL | ML-DSA-87 signature over all other fields |

**Verification**: for each chunk, compute `SHA3-512(chunk.sign_b64)` and compare against `chunk_sign_hashes[chunk_index]`. Since each chunk's `sign_b64` covers the chunk's data hash, this transitively binds chunk data integrity to the `files` manifest signature.

### 1.2 `file_chunks` (Electric-synced)

One row per chunk. Contains the actual encrypted blob data. Uploaded via the standard ingest endpoint (`data_b64` provided as base64 in the ingest payload). Client-signed for integrity.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, NOT NULL | Parent file reference |
| `chunk_index` | INTEGER, NOT NULL | 0-based position |
| `data_b64` | BYTEA, NOT NULL | Encrypted chunk blob (~4 MB). **STORAGE EXTERNAL** |
| `size` | INTEGER, NOT NULL | Encrypted chunk byte size |
| `uploader_hash` | TEXT, NOT NULL | FK-like → user_cards |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `sign_b64` | BYTEA, NOT NULL | Signature over `(file_id, chunk_index, SHA3-512(data_b64), size, uploader_hash, owner_timestamp)` |
| | PK | `(file_id, chunk_index)` |

The `sign_b64` covers a **hash** of `data_b64`, not `data_b64` itself — the signature payload includes `SHA3-512(data_b64)` so verification does not require re-reading the blob. This hash is what `files.chunk_sign_hashes` binds to.

**Sync filtering** (in ShapeWriter): on receiving a `file_chunk` via Electric, skip it if:
- No matching `files` row exists for this `file_id`, OR
- The `files.uploader_hash` differs from the chunk's `uploader_hash`

This prevents unbounded storage from unverified chunks during device-to-device sync.

### 1.3 `upload_chunks` (local only, NOT Electric-synced)

Tracks uploaded chunks before the signed `files` manifest arrives. Populated as a side effect of `file_chunks` ingest — the device writes a bookkeeping row with server-set `updated_at` from TimeKeeper. Provides ownership tracking, upload resume, and unsigned-data budget accounting.

| Column | Type | Description                      |
|---|---|----------------------------------|
| `file_id` | TEXT | Client-provided `"f_" + UUIDv7` |
| `chunk_index` | INTEGER | Position in file                 |
| `chunk_sign_hash` | BYTEA, NOT NULL | `SHA3-512(chunk.sign_b64)` — matches `files.chunk_sign_hashes` for GC verification |
| `uploader_hash` | TEXT, NOT NULL | Who uploaded this chunk          |
| `size` | INTEGER, NOT NULL | Blob byte size                   |
| `updated_at` | BIGINT, NOT NULL | Unix seconds (from TimeKeeper)   |
| | PK | `(file_id, chunk_index)`         |

Indexes: `uploader_hash` (budget queries), `updated_at` (GC queries).

**Queries this table supports**:
- **Resume**: `WHERE file_id = ?` — client queries which indexes are already uploaded
- **Unsigned budget**: `SUM(size) WHERE uploader_hash = ? AND file_id NOT IN (SELECT file_id FROM files)` — uncommitted bytes per user; device rejects further uploads if exceeded
- **GC**: `WHERE updated_at < threshold AND file_id NOT IN (SELECT file_id FROM files)` — delete stale rows + orphan `file_chunks` rows

## 2. Chunk Encryption

All encryption/decryption happens client-side (browser, Web Crypto API).

- **Algorithm**: AES-256-GCM
- **Key**: `enc_secret` — random 32 bytes, unique per file
- **Nonce**: 12 bytes — `chunk_index` zero-padded to 12 bytes (deterministic)
- **Auth tag**: 16 bytes, appended to ciphertext (standard GCM output)

```
encrypted_chunk = AES-256-GCM(enc_secret, nonce=pad(chunk_index, 12), plaintext_chunk)
```

Nonce safety: `enc_secret` is unique per file (no reuse across files), `chunk_index` is unique within file (no reuse within file). The 2^32 nonce space supports files up to ~16 TB per key.

## 3. Content Type

The `"file"` content type and its positional array schema are defined in [07_content_polymorphism.md § `"file"`](../electric/pq_data_layer/07_content_polymorphism.md#file).

## 4. Upload Protocol

All uploads use the standard ingest endpoint — no dedicated file upload endpoints.

```
Client                              Device
  │                                    │
  │─── GET /electric/v1/challenge ────>│  PoP authentication
  │<── {challenge_id, challenge} ──────│
  │                                    │
  │  encrypt chunk 0 client-side       │
  │  sign chunk (file_id, index,       │
  │    SHA3-512(data_b64), size,       │
  │    uploader, owner_timestamp)      │
  │─── POST /electric/v1/ingest ──────>│  file_chunks insert, data_b64 as base64
  │    device: verify sign_b64         │
  │    insert into file_chunks         │
  │    insert into upload_chunks        │
  │      (updated_at = TimeKeeper)     │
  │<── 200 {txid} ─────────────────────│
  │                                    │
  │  encrypt chunk 1 ...               │
  │─── POST /electric/v1/ingest ──────>│  same flow
  │<── 200 {txid} ─────────────────────│
  │─── ...                             │  progressive encrypt + upload
  │                                    │
  │  resume: query Electric shape      │
  │  for file_chunks WHERE file_id=?   │
  │  → learn which chunk_indexes exist │
  │                                    │
  │  all chunks uploaded               │
  │  build files manifest with         │
  │    chunk_sign_hashes array         │
  │    (computed locally from own      │
  │     sign_b64 values)               │
  │  sign manifest                     │
  │─── POST /electric/v1/ingest ──────>│  files insert
  │    device verifies:                │
  │      1. sign_b64 on files          │
  │      2. all chunk_count rows       │
  │         exist in file_chunks       │
  │      3. each chunk_sign_hash       │
  │         matches actual chunk       │
  │    delete upload_chunks rows        │
  │      for this file_id              │
  │<── 200 {txid} ─────────────────────│  committed to Electric
```

The client encrypts, signs, and uploads chunks progressively via ingest (no need to encrypt everything upfront). The device verifies each chunk's signature on ingest and writes a local `upload_chunks` bookkeeping row (with server-set `updated_at` from TimeKeeper) for budget/GC tracking. After all chunks are on the device, the client builds the `files` manifest with `chunk_sign_hashes` (computed locally from its own `sign_b64` values), signs it, and commits via ingest. The device validates that all chunks are present before accepting the `files` row.

## 5. Sync Protocol

When Device B receives rows via Electric:

1. **`files` row arrives** → verify `ML-DSA-87` signature → store locally
2. **`file_chunks` rows arrive** → for each:
   - Check: does a `files` row exist for this `file_id`?
   - Check: is `files.deleted_flag` false?
   - Check: does `files.uploader_hash` match `chunk.uploader_hash`?
   - If all yes → verify chunk signature → store locally
   - If any no → **skip** (do not store, do not waste disk)
3. **File is available** once `files.chunk_count` matches count of stored `file_chunks`

**Ordering**: Electric may deliver `file_chunks` before the `files` manifest. Chunks without a matching `files` row are skipped (not stored). When a `files` row arrives, the receiving device checks whether all `chunk_count` chunks are present locally. If any are missing (skipped during earlier sync), it opens a short-lived Electric shape with a WHERE filter for the specific missing chunks (`file_id = $1 AND chunk_index IN ($2, $3, ...)`) and fetches only those.

## 6. Download Protocol

### 6.1 Direct Chunk Endpoint

```
GET /electric/v1/file_chunk/:file_id/:chunk_index
```

Returns the raw `data_b64` BYTEA as `application/octet-stream`. Response header `x-chunk-size` carries the chunk's `size` value.

**Implementation**: `ChatWeb.FileChunkController.show/2` → `Chat.Data.File.get_file_chunk/2` (single PG primary-key lookup).

**Why not Electric shapes?** Each unique `(table, where)` combination creates a persistent Electric shape: a Consumer GenServer, a PG snapshot transaction, disk-backed shape log, and ongoing WAL filtering. Fetching N chunks via shapes (one shape per `file_id + chunk_index` WHERE clause) creates N long-lived server-side resources for what is a simple point read. The direct endpoint performs one PG query with no persistent overhead. This matters especially for video streaming (see [pq_video_streaming.md §6](pq_video_streaming.md#6-chunk-fetch-strategy)), where seeking triggers many single-chunk fetches.

### 6.2 Download Flow

```
Client                              Device
  │                                    │
  │─── GET /electric/v1/shapes ───────>│  fetch files manifest
  │    ?table=files&where=file_id=?    │  (one Electric shape, small row)
  │<── {chunk_count, chunk_sign_hashes}│
  │                                    │
  │  for i in 0..chunk_count-1:        │
  │─── GET /electric/v1/file_chunk ───>│  direct endpoint, raw binary
  │       /:file_id/:i                 │
  │<── application/octet-stream ───────│  x-chunk-size header
  │  verify chunk signature            │
  │  decrypt with AES-256-GCM          │
  │  append to output                  │
```

The `files` manifest is fetched once via an Electric shape (small row, acceptable overhead). Individual chunks use the direct endpoint — no shape creation per chunk.

## 7. Deletion Protocol

To delete a file, the client updates the `files` row:
1. Set `deleted_flag = true`
2. Set `chunk_sign_hashes = '{}'` (empty array)
3. Re-sign the row

Emptying `chunk_sign_hashes` ensures receiving devices cannot verify any chunks for this file, so the sync protocol (§5) will skip them. The signed update propagates via Electric to all devices, where GC (§8) reclaims the chunk data.

## 8. Garbage Collection

Runs every hour. Two triggers clean up `file_chunks` and `upload_chunks` rows:

1. **Deleted files**: when `files.deleted_flag = true`, delete all `file_chunks` rows for that `file_id`
2. **Stale uploads**: when `upload_chunks.updated_at + 2 days < TimeKeeper.now()`, delete the `upload_chunks` row and its corresponding `file_chunks` row (upload never completed)

Trigger 1 handles normal file deletion. Trigger 2 handles abandoned uploads where the `files` manifest was never ingested.

## 9. PostgreSQL Storage Configuration

### 9.1 STORAGE EXTERNAL

Encrypted blobs are high-entropy and will not compress. PostgreSQL will waste CPU attempting LZ4 compression on every write, then store uncompressed anyway. Set storage to `EXTERNAL` to skip compression and store out-of-line directly:

```sql
ALTER TABLE file_chunks ALTER COLUMN data_b64 SET STORAGE EXTERNAL;
```

### 9.2 AUTOVACUUM Tuning

`file_chunks` has write-once semantics: chunks are inserted, never updated, eventually deleted. But each dead row carries ~4 MB of TOAST data — even a few dead rows mean significant bloat on a 4 GB RAM device.

```sql
ALTER TABLE file_chunks SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay = 40
);
```

| Setting | Value | Default | Rationale |
|---|---|---|---|
| `vacuum_scale_factor` | 0.01 (1%) | 0.20 (20%) | Trigger vacuum early — each dead row is ~4 MB of TOAST bloat |
| `analyze_scale_factor` | 0.02 (2%) | 0.10 (10%) | Keep planner statistics fresh as chunks are added/removed |
| `vacuum_cost_delay` | 40 ms | 2 ms | Reduce I/O pressure on USB/SD storage, spread vacuum cost over longer periods |

### 9.3 WAL Considerations

`file_chunks` is in the Electric publication — 4 MB blob INSERTs go through WAL and logical replication:

- **2-3x write amplification** per chunk (WAL + heap + possible full-page write)
- 100 MB file (25 chunks) → ~200-300 MB WAL burst
- `max_wal_size = 512MB` (doubled from 256 MB to accommodate concurrent file uploads)
- `wal_compression = on` is already enabled but provides no benefit for encrypted (high-entropy) data

## 10. Hardware Constraints

### 10.1 Device Memory
- **Total RAM**: 4 GB, shared between PostgreSQL and the Elixir/Erlang application
- Chunk size must be small enough that the device can buffer a chunk during transfer (device does not encrypt/decrypt — it stores and serves opaque blobs)
- At 4 MB per chunk, the device needs ~4-8 MB to buffer a chunk during ingest — well within budget

### 10.2 Storage
- PostgreSQL stores all chunk data in TOAST tables (no filesystem sharding needed)
- FAT directory limitations are irrelevant — all data is inside the database

## 11. Cryptographic Constraints

### 11.1 AES-256-GCM
- **Per-key data limit**: ~64 GB (2^32 blocks x 16 bytes)
- **No streaming mode**: GCM requires the entire plaintext in memory for encryption/decryption (authentication tag is computed over the full message)
- **Nonce**: 12 bytes (96 bits), must be unique per encryption under the same key
- **Auth tag**: 16 bytes per chunk

### 11.2 Nonce Exhaustion
- With **random 96-bit nonces**, collision probability becomes meaningful after ~2^32 messages per key (birthday bound)
- At 4 MB chunks, 2^32 messages = ~16 TB per key before nonce collision risk
- **Deterministic nonce scheme** (e.g., chunk index) eliminates collision risk but requires careful design to avoid reuse across different files under the same key

### 11.3 Client-Side Encryption
- All encryption/decryption happens **exclusively in the browser** (Web Crypto API / SubtleCrypto)
- The device (server) never sees plaintext — it stores, serves, and transfers opaque encrypted chunks
- At 4 MB chunks, browser needs ~10 MB per encryption (plaintext + ciphertext + overhead) — safe on all modern devices including mobile
- SubtleCrypto does not natively support streaming AES-GCM

## 12. Chunk Size Decision

### 12.1 Chosen Size: 4 MB

**Rationale**:
- Fits comfortably in browser memory for AES-GCM (~10 MB working set per chunk)
- 4x fewer rows than 1 MB — reduces TOAST entries, row overhead, and `chunk_sign_hashes` array size
- Allows SHA3-512 for hashing (64 bytes per entry) while keeping manifest size reasonable: 1 TB file = 256K entries × 64 bytes = 16 MB
- Unifies hashing with existing `EnigmaPq.hash/1` (SHA3-512) — no separate hash function needed
- Device only buffers opaque encrypted blobs during transfer — no crypto overhead on device
- Acceptable resumability on LAN/WiFi connections (4 MB retry on failure)

### 12.2 Trade-offs Considered

| Alternative | Pro | Con |
|---|---|---|
| 1 MB | Fine-grained resume; smaller WAL writes | 4x more rows; forces SHA3-256 to keep manifest size down; needs separate hash function |
| 4 MB (chosen) | Balanced — enables SHA3-512, reasonable row count | 4 MB retry on resume; ~8-12 MB WAL per write |
| 8-16 MB | Smallest manifests | Memory pressure on low-end mobile; large WAL bursts; poor resumability |

## 13. Resolved Questions

- **Unsigned budget**: no explicit budget — GC (§8, trigger 2) clears stale unsigned data after 2 days.
- **Max file size**: 1 TB hard cap.
- **Partial file availability**: client's call — the client decides when to start downloading/decrypting. For videos, streaming before all chunks are synced makes sense.
- **WAL sizing**: `max_wal_size = 512 MB` to accommodate concurrent 4 MB chunk uploads with write amplification.
- **Hash algorithm**: SHA3-512 — matches `EnigmaPq.hash/1`, same Keccak family as ML-DSA-87's internal SHAKE-256. 64-byte output is acceptable at 4 MB chunk size (1 TB = 256K entries = 16 MB manifest).
- **Electric chunk re-delivery**: when `file_chunks` arrive before the `files` manifest, the device skips them. On `files` manifest arrival, if any chunks are missing, fetch them via a targeted Electric shape with a WHERE filter (`file_id = $1 AND chunk_index IN (...)`) — no full re-sync needed.

## 14. Migration Plan: Chunk Blobs → Filesystem (Protocol v2, raw bytes)

Move chunk payloads out of PostgreSQL onto the filesystem **and drop base64 from the chunk protocol end-to-end**. Manifests (`files`, `file_chunks` minus the blob, `upload_chunks`) stay in PG and in the Electric publication — coordination remains Electric's job; bytes move at filesystem speed, written once, raw.

Clients are at PoC stage, so this is a deliberate breaking protocol change (v2). Going raw eliminates a standing hazard: base64 is not canonical (padding, alphabets), and today the signature hashes one base64 representation while Electric/JSON transport may re-encode another. With raw bytes there is exactly one representation to hash, sign, store, and serve.

### 14.1 Motivation (measured on device)

Benchmark on RPi4 (50 × 4 MiB incompressible blob inserts through `Chat.Repo`, `STORAGE EXTERNAL`, one commit per insert):

| Metric | Logged table | Unlogged table |
|---|---|---|
| Time per 4 MiB insert | 1100 ms (~3.6 MB/s) | 754 ms (~5.4 MB/s) |
| WAL generated | 214 MB per 208 MB data (1:1) | ~0 |

Findings that drive this plan:

- **WAL costs +46% time and 2x flash wear** per chunk — and since the platform runs PG with `fsync=off`, `synchronous_commit=off`, `full_page_writes=off` (`platform/lib/platform/tools/postgres/lifecycle.ex`), WAL buys **no power-loss durability** in exchange. Its only remaining value for blobs is logical replication transport.
- **`wal_compression=on` is a no-op** for our payloads: encrypted chunks are high-entropy; measured WAL ratio is exactly 1:1.
- **Base64 adds +33% on top of everything**: a 4 MB encrypted chunk is ~5.3 MB as `data_b64`, paid on disk, in WAL, in replication, and on the wire — in both directions.
- **Total write amplification today**: ~5.3 MB heap+TOAST + ~5.3 MB WAL per 4 MB chunk ≈ 2.7x, before any replication re-write. A 100 MB upload causes a ~270 MB device write burst against `max_wal_size`, forcing continuous checkpoints that stall all other writers.
- Existing workarounds are symptoms of this design: `ElectricIngestThrottle` (multi-MB JSON ingest payloads), aggressive autovacuum overrides on `file_chunks` (§9.2), batched GC deletes, doubled `max_wal_size` (§9.3).

What does **not** change: client-side encryption (§2), the manifest trust model (`files` binds chunks via `chunk_sign_hashes`, §1.1), upload resume semantics, GC triggers (§8).

### 14.2 Protocol v2 Changes

| Aspect | v1 (current, §1-13) | v2 |
|---|---|---|
| Chunk payload at rest | `data_b64` BYTEA in PG (base64 text) | Raw encrypted bytes in FS file |
| Signed hash | `SHA3-512(data_b64)` (over base64) | `SHA3-512(raw encrypted bytes)` |
| Chunk upload | JSON ingest, base64 in payload | `PUT /electric/v1/file_chunk/:file_id/:chunk_index`, raw `application/octet-stream` body |
| Chunk download | base64 bytes as octet-stream | raw bytes as octet-stream (-25% wire) |
| `files` manifest upload | JSON ingest | unchanged (JSON ingest) |
| `file_chunks` schema | includes `data_b64` | manifest-only + new `data_hash` column |

**v2 `file_chunks` (manifest)**: `file_id`, `chunk_index`, `data_hash` (BYTEA, `SHA3-512(raw)` — stored explicitly so fetch/read verification never parses signatures), `size`, `uploader_hash`, `owner_timestamp`, `sign_b64`. PK `(file_id, chunk_index)`. Rows shrink from ~5.3 MB to ~5 KB (dominated by the ML-DSA-87 signature), so the table stays in the Electric publication for free. Signature payload becomes `(file_id, chunk_index, data_hash, size, uploader_hash, owner_timestamp)` — same shape as v1, hash now over raw bytes. `files.chunk_sign_hashes` binding (`SHA3-512(chunk.sign_b64)`) is untouched.

**Chunk upload endpoint** (replaces §4's "no dedicated file upload endpoints" for chunks): raw body, metadata + signature + PoP challenge in headers. Server: verify signature → `ChunkStore.put` → insert `file_chunks` manifest + `upload_chunks` rows in one transaction. No multi-MB JSON parsing, no base64 decode, no Writer overhead on the hot path — `ElectricIngestThrottle` becomes unnecessary. FS write happens before the PG transaction commits; if the transaction rolls back, the orphan file is reclaimed by GC (§14.5).

### 14.3 Target Architecture

```
  PUT chunk (raw) ──verify sig──> ChunkStore (FS, raw bytes)
                       └────────> file_chunks manifest + upload_chunks ─┐
  ingest (JSON) ──verify────────> files manifest ───────────────────────┤
                                                                        ▼
                                                            PG / Electric publication
                                                                        │
  GET /file_chunk ◄── send_file ── ChunkStore ◄── ChunkFetcher ◄── manifest sync (peers)
```

**`Chat.Data.File.ChunkStore`** (new, `Chat.FileFs`-style):

- Path layout: `<data_dir>/pq_files/<file_id[0..1]>/<file_id>/<chunk_index>` (two-char shard keeps directories small for FAT/exFAT drives).
- Content: raw encrypted bytes, exactly what `data_hash` covers — one representation everywhere.
- Writes: temp file + `rename/2`; free-space check before write (reject upload with 413).
- API mirrors usage sites: `put(file_id, idx, bin)`, `fetch(file_id, idx)`, `exists?/2`, `delete_file(file_id)`, `stream/3` for ranged reads (video seeking, pq_video_streaming.md §6, becomes `send_file` offset/length).

**Download path**: `FileChunkController.show/2` serves from `ChunkStore` via `send_file` (zero-copy: no TOAST reassembly, no BEAM blob copy, no base64). Client verifies `SHA3-512(raw)` against the manifest and decrypts directly.

**Device-to-device sync**: manifest rows arrive via Electric/`ShapeWriter` with the same §5 filtering. Since rows no longer carry bytes, a new **`ChunkFetcher`** worker fills the gap: when a verified manifest row is written and `ChunkStore.exists?/2` is false, it queues `GET /electric/v1/file_chunk/...` against the peer that served the shape, verifies the body against `data_hash`, and stores the file. Fetches are sequential with bounded retry — bulk bytes stop competing with Electric's WAL pipeline. "File available" (§5.3) becomes: manifest complete **and** all chunk files present.

### 14.4 Migration Steps (PoC cutover — no backfill)

Existing chunk data is PoC-stage and disposable; v1 signatures hash base64 bytes and cannot be re-signed server-side, so legacy rows are dropped rather than converted.

| Step | Change |
|---|---|
| M1 | Ship `ChunkStore`, v2 validation (`data_hash` over raw), `PUT`/`GET` chunk endpoints, `ChunkFetcher` |
| M2 | Migration: add `data_hash`, drop `data_b64`, `TRUNCATE file_chunks, upload_chunks`; mark or clear orphaned `files` rows (re-upload as needed) |
| M3 | Switch SPA upload/download to v2 (raw PUT, raw GET, raw hashing) |
| M4 | Revert PG accommodations: `max_wal_size` back to 256 MB, drop autovacuum overrides on `file_chunks` (§9.2 obsolete — rows are small now), remove `ElectricIngestThrottle` |

If some deployment turns out to need its v1 data: one-off script decodes `data_b64` → ChunkStore, sets `data_hash = SHA3-512(raw)`, and re-verification of those rows uses the legacy rule (`SHA3-512(base64(raw))` against `sign_b64`). Kept out of the main plan deliberately.

### 14.5 Failure Modes

| Failure | Mitigation |
|---|---|
| Crash mid-FS-write | Temp-file + rename; GC sweeps `*.tmp` older than 1 h |
| PG txn rolls back after FS write | Orphan file with no manifest row; GC sweep deletes FS entries with no `file_chunks` row after a 2-day grace (mirrors §8 trigger 2) |
| FS file lost/corrupt (SD bitrot) | `data_hash` check on read/fetch; on mismatch delete + re-fetch via `ChunkFetcher` if a peer has it; else surface file as incomplete. Today's PG path has **no** integrity check on read — strict improvement |
| Power loss | At parity or better: PG with `fsync=off` risks whole-cluster corruption; FS loses at most in-flight chunk files, which are re-fetchable |
| FAT/exFAT semantics (weak rename atomicity, no dir fsync) | Accepted — equivalent risk class to current `fsync=off` PG. §10.2's "FAT limitations are irrelevant" no longer holds; the 2-level shard keeps per-directory entry counts low |
| Disk full | `ChunkStore.put` checks free space and fails the upload cleanly (413); GC unaffected |
| Peer unavailable during `ChunkFetcher` pull | Bounded retry with backoff; missing chunks re-queued when the peer's shape reconnects |

### 14.6 Expected Gains

Per 100 MB upload (26 chunks):

| | v1 (PG + base64) | v2 (FS, raw) |
|---|---|---|
| Bytes on the wire (up + down) | ~133 MB each way | 100 MB each way |
| Device bytes written | ~270 MB (heap+TOAST + WAL, base64) | 100 MB (raw file, written once) |
| WAL burst | ~133 MB → checkpoint storm | ~130 KB (manifest rows) |
| Ingest write speed (measured class) | ~3.6 MB/s | raw storage speed (≥2x) |
| Dead-tuple bloat per deleted file | ~133 MB TOAST awaiting vacuum | `rm -r` of one directory |

Secondary effects: Electric stops parsing multi-MB WAL records; recovery time shrinks (WAL stays small — the stated goal of `recovery_optimized_settings`); `pg_dump`/healing of the chunk DB becomes proportional to metadata, not content; one hash representation kills the base64-canonicalization bug class; browser saves a base64 decode per chunk.

### 14.7 Open Questions

- **Peer addressing for `ChunkFetcher`**: single-peer topologies can reuse the shape source address; multi-peer needs a chunk-availability hint (possibly a column on `files` or probing peers in order).
- **Backup story**: drive backup tooling must now include `<data_dir>/pq_files` alongside the PG data dir.
- **PoP on the binary endpoint**: reuse the challenge flow from ingest via headers, or accept the chunk signature itself as proof (it covers uploader + monotonic timestamp). Needs a decision before M1.
- **`upload_chunks` and budget queries (§1.3)**: unchanged — sizes live in manifest rows; only the blob moved.

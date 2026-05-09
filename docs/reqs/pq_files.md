# File Storage

Constraints, design, and schema for storing large files on BuckitUp platform devices. All chunk data lives in PostgreSQL — no filesystem storage. See also [PostgreSQL Constraints](pg_constraints.md) for TOAST, WAL amplification, and VACUUM considerations affecting large-value columns.

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

### 1.3 `upload_files` (local only, NOT Electric-synced)

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
  │    insert into upload_files        │
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
  │    delete upload_files rows        │
  │      for this file_id              │
  │<── 200 {txid} ─────────────────────│  committed to Electric
```

The client encrypts, signs, and uploads chunks progressively via ingest (no need to encrypt everything upfront). The device verifies each chunk's signature on ingest and writes a local `upload_files` bookkeeping row (with server-set `updated_at` from TimeKeeper) for budget/GC tracking. After all chunks are on the device, the client builds the `files` manifest with `chunk_sign_hashes` (computed locally from its own `sign_b64` values), signs it, and commits via ingest. The device validates that all chunks are present before accepting the `files` row.

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

## 6. Deletion Protocol

To delete a file, the client updates the `files` row:
1. Set `deleted_flag = true`
2. Set `chunk_sign_hashes = '{}'` (empty array)
3. Re-sign the row

Emptying `chunk_sign_hashes` ensures receiving devices cannot verify any chunks for this file, so the sync protocol (§5) will skip them. The signed update propagates via Electric to all devices, where GC (§7) reclaims the chunk data.

## 7. Garbage Collection

Runs every hour. Two triggers clean up `file_chunks` and `upload_files` rows:

1. **Deleted files**: when `files.deleted_flag = true`, delete all `file_chunks` rows for that `file_id`
2. **Stale uploads**: when `upload_files.updated_at + 2 days < TimeKeeper.now()`, delete the `upload_files` row and its corresponding `file_chunks` row (upload never completed)

Trigger 1 handles normal file deletion. Trigger 2 handles abandoned uploads where the `files` manifest was never ingested.

## 8. PostgreSQL Storage Configuration

### 8.1 STORAGE EXTERNAL

Encrypted blobs are high-entropy and will not compress. PostgreSQL will waste CPU attempting LZ4 compression on every write, then store uncompressed anyway. Set storage to `EXTERNAL` to skip compression and store out-of-line directly:

```sql
ALTER TABLE file_chunks ALTER COLUMN data_b64 SET STORAGE EXTERNAL;
```

### 8.2 AUTOVACUUM Tuning

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

### 8.3 WAL Considerations

`file_chunks` is in the Electric publication — 4 MB blob INSERTs go through WAL and logical replication:

- **2-3x write amplification** per chunk (WAL + heap + possible full-page write)
- 100 MB file (25 chunks) → ~200-300 MB WAL burst
- `max_wal_size = 512MB` (doubled from 256 MB to accommodate concurrent file uploads)
- `wal_compression = on` is already enabled but provides no benefit for encrypted (high-entropy) data

## 9. Hardware Constraints

### 9.1 Device Memory
- **Total RAM**: 4 GB, shared between PostgreSQL and the Elixir/Erlang application
- Chunk size must be small enough that the device can buffer a chunk during transfer (device does not encrypt/decrypt — it stores and serves opaque blobs)
- At 4 MB per chunk, the device needs ~4-8 MB to buffer a chunk during ingest — well within budget

### 9.2 Storage
- PostgreSQL stores all chunk data in TOAST tables (no filesystem sharding needed)
- FAT directory limitations are irrelevant — all data is inside the database

## 9. Cryptographic Constraints

### 9.3 AES-256-GCM
- **Per-key data limit**: ~64 GB (2^32 blocks x 16 bytes)
- **No streaming mode**: GCM requires the entire plaintext in memory for encryption/decryption (authentication tag is computed over the full message)
- **Nonce**: 12 bytes (96 bits), must be unique per encryption under the same key
- **Auth tag**: 16 bytes per chunk

### 9.4 Nonce Exhaustion
- With **random 96-bit nonces**, collision probability becomes meaningful after ~2^32 messages per key (birthday bound)
- At 4 MB chunks, 2^32 messages = ~16 TB per key before nonce collision risk
- **Deterministic nonce scheme** (e.g., chunk index) eliminates collision risk but requires careful design to avoid reuse across different files under the same key

### 9.5 Client-Side Encryption
- All encryption/decryption happens **exclusively in the browser** (Web Crypto API / SubtleCrypto)
- The device (server) never sees plaintext — it stores, serves, and transfers opaque encrypted chunks
- At 4 MB chunks, browser needs ~10 MB per encryption (plaintext + ciphertext + overhead) — safe on all modern devices including mobile
- SubtleCrypto does not natively support streaming AES-GCM

## 10. Chunk Size Decision

### 10.1 Chosen Size: 4 MB

**Rationale**:
- Fits comfortably in browser memory for AES-GCM (~10 MB working set per chunk)
- 4x fewer rows than 1 MB — reduces TOAST entries, row overhead, and `chunk_sign_hashes` array size
- Allows SHA3-512 for hashing (64 bytes per entry) while keeping manifest size reasonable: 1 TB file = 256K entries × 64 bytes = 16 MB
- Unifies hashing with existing `EnigmaPq.hash/1` (SHA3-512) — no separate hash function needed
- Device only buffers opaque encrypted blobs during transfer — no crypto overhead on device
- Acceptable resumability on LAN/WiFi connections (4 MB retry on failure)

### 10.2 Trade-offs Considered

| Alternative | Pro | Con |
|---|---|---|
| 1 MB | Fine-grained resume; smaller WAL writes | 4x more rows; forces SHA3-256 to keep manifest size down; needs separate hash function |
| 4 MB (chosen) | Balanced — enables SHA3-512, reasonable row count | 4 MB retry on resume; ~8-12 MB WAL per write |
| 8-16 MB | Smallest manifests | Memory pressure on low-end mobile; large WAL bursts; poor resumability |

## 11. Resolved Questions

- **Unsigned budget**: no explicit budget — GC (§6, trigger 2) clears stale unsigned data after 2 days.
- **Max file size**: 1 TB hard cap.
- **Partial file availability**: client's call — the client decides when to start downloading/decrypting. For videos, streaming before all chunks are synced makes sense.
- **WAL sizing**: `max_wal_size = 512 MB` to accommodate concurrent 4 MB chunk uploads with write amplification.
- **Hash algorithm**: SHA3-512 — matches `EnigmaPq.hash/1`, same Keccak family as ML-DSA-87's internal SHAKE-256. 64-byte output is acceptable at 4 MB chunk size (1 TB = 256K entries = 16 MB manifest).
- **Electric chunk re-delivery**: when `file_chunks` arrive before the `files` manifest, the device skips them. On `files` manifest arrival, if any chunks are missing, fetch them via a targeted Electric shape with a WHERE filter (`file_id = $1 AND chunk_index IN (...)`) — no full re-sync needed.

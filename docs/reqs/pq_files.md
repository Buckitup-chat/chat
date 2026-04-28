# File Storage

Constraints, design, and schema for storing large files on BuckitUp platform devices. All chunk data lives in PostgreSQL — no filesystem storage. See also [PostgreSQL Constraints](pg_constraints.md) for TOAST, WAL amplification, and VACUUM considerations affecting large-value columns.

## 1. Hardware Constraints

### 1.1 Device Memory
- **Total RAM**: 4 GB, shared between PostgreSQL and the Elixir/Erlang application
- Chunk size must be small enough that the device can buffer a chunk during transfer (device does not encrypt/decrypt — it stores and serves opaque blobs)

### 1.2 Storage
- PostgreSQL stores all chunk data in TOAST tables (no filesystem sharding needed)
- FAT directory limitations are irrelevant — all data is inside the database

## 2. Cryptographic Constraints

### 2.1 AES-256-GCM
- **Per-key data limit**: ~64 GB (2^32 blocks x 16 bytes)
- **No streaming mode**: GCM requires the entire plaintext in memory for encryption/decryption (authentication tag is computed over the full message)
- **Nonce**: 12 bytes (96 bits), must be unique per encryption under the same key
- **Auth tag**: 16 bytes per chunk

### 2.2 Nonce Exhaustion
- With **random 96-bit nonces**, collision probability becomes meaningful after ~2^32 messages per key (birthday bound)
- At 1 MB chunks, 2^32 messages = ~4 TB per key before nonce collision risk
- **Deterministic nonce scheme** (e.g., chunk index) eliminates collision risk but requires careful design to avoid reuse across different files under the same key

### 2.3 Client-Side Encryption
- All encryption/decryption happens **exclusively in the browser** (Web Crypto API / SubtleCrypto)
- The device (server) never sees plaintext — it stores, serves, and transfers opaque encrypted chunks
- Browser memory is constrained — large ArrayBuffers cause pressure
- SubtleCrypto does not natively support streaming AES-GCM

## 3. Chunk Size Decision

### 3.1 Chosen Size: 1 MB

**Rationale**:
- Fits comfortably in browser memory for AES-GCM (full plaintext required)
- Device only buffers opaque encrypted blobs during transfer — no crypto overhead on device
- Good resumability on unreliable connections
- Reasonable TOAST overhead per row (~1 MB per TOAST entry)

### 3.2 Trade-offs Considered

| Alternative | Pro | Con |
|---|---|---|
| 64-256 KB | Better resume granularity | Multiplies row count and TOAST entries; 1 GB file at 64 KB = ~16K rows |
| 4-8 MB | Less row overhead | Spikes browser memory on low-end devices; worse resumability; higher WAL amplification per write |
| 1 MB (chosen) | Balanced across all constraints | ~4.2M rows for a 4 TB file — large but manageable in PostgreSQL |

## 4. Chunk Encryption

All encryption/decryption happens client-side (browser, Web Crypto API).

- **Algorithm**: AES-256-GCM
- **Key**: `enc_secret` — random 32 bytes, unique per file
- **Nonce**: 12 bytes — `chunk_index` zero-padded to 12 bytes (deterministic)
- **Auth tag**: 16 bytes, appended to ciphertext (standard GCM output)

```
encrypted_chunk = AES-256-GCM(enc_secret, nonce=pad(chunk_index, 12), plaintext_chunk)
```

Nonce safety: `enc_secret` is unique per file (no reuse across files), `chunk_index` is unique within file (no reuse within file). The 2^32 nonce space supports files up to ~4 TB per key.

## 5. Content Type

File metadata lives inside the encrypted `content_b64` of the carrier message (see [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md)). The content type key is `"file"`, value is a positional array:

```json
{"file": [name, size, mime_type, file_id, enc_secret_b64, original_hash_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | name | Original filename |
| 1 | size | Plaintext byte size |
| 2 | mime_type | MIME type |
| 3 | file_id | References `files.file_id` |
| 4 | enc_secret_b64 | AES-256 key for chunk decryption (base64) |
| 5 | original_hash_b64 | SHA3-256 of plaintext file for end-to-end verification (base64) |

Because this lives inside ciphertext, the database cannot tell whether a row is text or a file attachment. Only dialog members who can decrypt `content_b64` learn the file exists and obtain `enc_secret` to decrypt chunks.

## 6. Tables

### 6.1 `files` (Electric-synced)

One row per completed file. Created only after all chunks are uploaded and verified. The trust anchor — a receiving device uses this row to decide whether to accept `file_chunks`.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, PK | `"fb_" + UUIDv7` |
| `uploader_hash` | TEXT, NOT NULL | FK-like → user_cards |
| `total_size` | BIGINT, NOT NULL | Plaintext file size in bytes |
| `chunk_size` | INTEGER, NOT NULL, DEFAULT 1048576 | Bytes per chunk (1 MB) |
| `chunk_count` | INTEGER, NOT NULL | Total number of chunks |
| `chunk_sign_hashes` | BYTEA[], NOT NULL | Array of `SHA3-256(chunk.sign_b64)` for each chunk, ordered by `chunk_index` |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `deleted_flag` | BOOLEAN, NOT NULL, DEFAULT false | Soft delete |
| `sign_b64` | BYTEA, NOT NULL | ML-DSA-87 signature over all other fields |

**Verification**: for each chunk, compute `SHA3-256(chunk.sign_b64)` and compare against `chunk_sign_hashes[chunk_index]`. Since each chunk's `sign_b64` covers the chunk's data hash, this transitively binds chunk data integrity to the `files` manifest signature.

### 6.2 `file_chunks` (Electric-synced)

One row per chunk. Contains the actual encrypted blob data. Uploaded via the standard ingest endpoint (`data` provided as base64 in the ingest payload). Client-signed for integrity.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, NOT NULL | Parent file reference |
| `chunk_index` | INTEGER, NOT NULL | 0-based position |
| `data` | BYTEA, NOT NULL | Encrypted chunk blob (~1 MB). **STORAGE EXTERNAL** |
| `size` | INTEGER, NOT NULL | Encrypted chunk byte size |
| `uploader_hash` | TEXT, NOT NULL | FK-like → user_cards |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `sign_b64` | BYTEA, NOT NULL | Signature over `(file_id, chunk_index, SHA3-256(data), size, uploader_hash, owner_timestamp)` |
| | PK | `(file_id, chunk_index)` |

The `sign_b64` covers a **hash** of `data`, not `data` itself — the signature payload includes `SHA3-256(data)` so verification does not require re-reading the blob. This hash is what `files.chunk_sign_hashes` binds to.

**Sync filtering** (in ShapeWriter): on receiving a `file_chunk` via Electric, skip it if:
- No matching `files` row exists for this `file_id`, OR
- The `files.uploader_hash` differs from the chunk's `uploader_hash`

This prevents unbounded storage from unverified chunks during device-to-device sync.

### 6.3 `upload_files` (local only, NOT Electric-synced)

Tracks uploaded chunks before the signed `files` manifest arrives. Populated as a side effect of `file_chunks` ingest — the device writes a bookkeeping row with server-set `updated_at` from TimeKeeper. Provides ownership tracking, upload resume, and unsigned-data budget accounting.

| Column | Type | Description                      |
|---|---|----------------------------------|
| `file_id` | TEXT | Client-provided `"fb_" + UUIDv7` |
| `chunk_index` | INTEGER | Position in file                 |
| `chunk_hash` | BYTEA, NOT NULL | `SHA3-256(encrypted blob)`       |
| `uploader_hash` | TEXT, NOT NULL | Who uploaded this chunk          |
| `size` | INTEGER, NOT NULL | Blob byte size                   |
| `updated_at` | BIGINT, NOT NULL | Unix seconds (from TimeKeeper)   |
| | PK | `(file_id, chunk_index)`         |

Indexes: `uploader_hash` (budget queries), `updated_at` (GC queries).

**Queries this table supports**:
- **Resume**: `WHERE file_id = ?` — client queries which indexes are already uploaded
- **Unsigned budget**: `SUM(size) WHERE uploader_hash = ? AND file_id NOT IN (SELECT file_id FROM files)` — uncommitted bytes per user; device rejects further uploads if exceeded
- **GC**: `WHERE updated_at < threshold AND file_id NOT IN (SELECT file_id FROM files)` — delete stale rows + orphan `file_chunks` rows

## 7. PostgreSQL Storage Configuration

### 7.1 STORAGE EXTERNAL

Encrypted blobs are high-entropy and will not compress. PostgreSQL will waste CPU attempting LZ4 compression on every write, then store uncompressed anyway. Set storage to `EXTERNAL` to skip compression and store out-of-line directly:

```sql
ALTER TABLE file_chunks ALTER COLUMN data SET STORAGE EXTERNAL;
```

### 7.2 AUTOVACUUM Tuning

`file_chunks` has write-once semantics: chunks are inserted, never updated, eventually deleted. But each dead row carries ~1 MB of TOAST data — even a few dead rows mean significant bloat on a 4 GB RAM device.

```sql
ALTER TABLE file_chunks SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay = 40
);
```

| Setting | Value | Default | Rationale |
|---|---|---|---|
| `vacuum_scale_factor` | 0.01 (1%) | 0.20 (20%) | Trigger vacuum early — each dead row is ~1 MB of TOAST bloat |
| `analyze_scale_factor` | 0.02 (2%) | 0.10 (10%) | Keep planner statistics fresh as chunks are added/removed |
| `vacuum_cost_delay` | 40 ms | 2 ms | Reduce I/O pressure on USB/SD storage, spread vacuum cost over longer periods |

### 7.3 WAL Considerations

`file_chunks` is in the Electric publication — 1 MB blob INSERTs go through WAL and logical replication:

- **2-3x write amplification** per chunk (WAL + heap + possible full-page write)
- 100 MB file (100 chunks) → ~200-300 MB WAL burst
- `max_wal_size = 512MB` (doubled from 256 MB to accommodate concurrent file uploads)
- `wal_compression = on` is already enabled but provides no benefit for encrypted (high-entropy) data

## 8. Upload Protocol

All uploads use the standard ingest endpoint — no dedicated file upload endpoints.

```
Client                              Device
  │                                    │
  │─── GET /electric/v1/challenge ────>│  PoP authentication
  │<── {challenge_id, challenge} ──────│
  │                                    │
  │  encrypt chunk 0 client-side       │
  │  sign chunk (file_id, index,       │
  │    SHA3-256(data), size,           │
  │    uploader, owner_timestamp)      │
  │─── POST /electric/v1/ingest ──────>│  file_chunks insert, data as base64
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

## 9. Sync Protocol

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

## 10. Garbage Collection

Runs every hour. Two triggers clean up `file_chunks` and `upload_files` rows:

1. **Deleted files**: when `files.deleted_flag = true`, delete all `file_chunks` rows for that `file_id`
2. **Stale uploads**: when `upload_files.updated_at + 2 days < TimeKeeper.now()`, delete the `upload_files` row and its corresponding `file_chunks` row (upload never completed)

Trigger 1 handles normal file deletion. Trigger 2 handles abandoned uploads where the `files` manifest was never ingested.

## 11. Resolved Questions

- **Unsigned budget**: no explicit budget — GC (§10, trigger 2) clears stale unsigned data after 2 days.
- **Max file size**: 1 TB hard cap.
- **Partial file availability**: client's call — the client decides when to start downloading/decrypting. For videos, streaming before all chunks are synced makes sense.
- **WAL sizing**: increase `max_wal_size` to 512 MB (double the current 256 MB) to accommodate concurrent file uploads.

- **Electric chunk re-delivery**: when `file_chunks` arrive before the `files` manifest, the device skips them. On `files` manifest arrival, if any chunks are missing, fetch them via a targeted Electric shape with a WHERE filter (`file_id = $1 AND chunk_index IN (...)`) — no full re-sync needed.

# File Storage

Constraints, design, and schema for storing large files on BuckitUp platform devices.

## 1. Hardware Constraints

### 1.1 Device Memory
- **Total RAM**: 4 GB, shared between PostgreSQL and the Elixir/Erlang application
- Chunk size must be small enough that the device can buffer a chunk during transfer (device does not encrypt/decrypt — it stores and serves opaque blobs)

### 1.2 Filesystem
- Storage medium uses **FAT** (possibly FAT16)
- **FAT16 root directory**: 512 entries (fixed at format time)
- **FAT16 subdirectory**: up to ~65,536 entries, but long filenames (LFN) consume multiple entries (each LFN segment holds 13 characters) — a typical filename uses 3 directory entries, reducing effective capacity to ~21,000 files per directory
- **FAT16 max file size**: 2 GB
- **FAT uses linear directory scan** (no B-tree) — large directories degrade performance
- A 4 TB file at 1 MB chunks would produce ~4.2 million chunk files — far beyond any single FAT directory limit

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
- Negligible cluster waste on FAT16 (even with 64 KB clusters)
- Good resumability on unreliable connections
- Well within FAT16 per-file size limit

### 3.2 Trade-offs Considered

| Alternative | Pro | Con |
|---|---|---|
| 64-256 KB | Better resume granularity | Multiplies metadata and FAT directory entries; 1 GB file at 64 KB = ~16K entries |
| 4-8 MB | Less metadata overhead, fewer FS entries | Spikes browser memory on low-end devices; worse resumability |
| 1 MB (chosen) | Balanced across all constraints | ~4.2M chunks for a 4 TB file — requires directory sharding |

## 4. Metadata Budget

### 4.1 Per-File Metadata (stored once)

| Field | Size |
|---|---|
| AES-256 key | 32 B |
| File hash / folder name (SHA-256) | 32-64 B |
| **Subtotal** | ~64 B |

### 4.2 Per-Chunk Metadata

**Minimal (with optimizations)**:

| Field | Size |
|---|---|
| Chunk index (u32) | 4 B |
| AES-GCM auth tag | 16 B |
| **Subtotal** | 20 B |

**Full (without optimizations)**:

| Field | Size |
|---|---|
| Start offset (u64) | 8 B |
| End offset (u64) | 8 B |
| AES-GCM IV/nonce (12 B) | 12 B |
| AES-GCM auth tag | 16 B |
| **Subtotal** | 44 B |

### 4.3 Total Metadata for 4 TB File (4,194,304 chunks)

| Variant | Per-chunk | Total |
|---|---|---|
| Full (offsets + IV + tag) | 44 B | ~176 MB |
| Optimized (index + tag, derived IVs) | 20 B | ~80 MB |

### 4.4 Optimization Notes
- **Drop offsets**: if all chunks are fixed 1 MB (last chunk is remainder), a 4-byte chunk index replaces both 8-byte offsets
- **Derive IVs from chunk index**: safe as long as the same key is never reused for a different file — saves 12 B per chunk (~50 MB at 4 TB scale)

## 5. FAT Directory Strategies

Storing millions of chunk files requires directory sharding to stay within FAT limits and maintain performance.

### 5.1 Nested Subdirectories
Split by hash prefix: `ab/cd/chunk_abcd0001.enc`. Two levels of 256 directories = 65,536 leaf directories, ~64 chunks each for a 4 TB file.

### 5.2 Container Files
Pack multiple chunks into larger container files (e.g., 256 chunks / 256 MB per container). Reduces 4.2M entries to ~16K files. Metadata index tracks offsets within containers.

### 5.3 Alternative Filesystem
ext4 or an append-only log file if the platform supports it — eliminates FAT directory limitations entirely.

## 6. Content Type

File metadata lives inside the encrypted `content_b64` of the carrier message (see [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md)). The content type key is `"file"`, value is a positional array:

```json
{"file": [name, size, mime_type, file_id, enc_secret_b64, original_hash_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | name | Original filename |
| 1 | size | Plaintext byte size |
| 2 | mime_type | MIME type |
| 3 | file_id | References `file_blobs.file_id` |
| 4 | enc_secret_b64 | AES-256 key for chunk decryption (base64) |
| 5 | original_hash_b64 | SHA3-256 of plaintext file for end-to-end verification (base64) |

Because this lives inside ciphertext, the database cannot tell whether a row is text or a file attachment. Only dialog members who can decrypt `content_b64` learn the file exists and obtain `enc_secret` to decrypt chunks.

## 7. Tables

### 7.1 `file_blobs` (Electric-synced)

One row per file. Signed by uploader. Replicated across devices via Electric SQL.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, PK | `"fb_" + UUIDv7` |
| `uploader_hash` | user_hash_type, NOT NULL | Who uploaded |
| `total_size` | BIGINT, NOT NULL | Plaintext file size in bytes |
| `chunk_size` | INTEGER, NOT NULL | Bytes per chunk (1048576) |
| `chunk_count` | INTEGER, NOT NULL | Total number of chunks |
| `chunks_digest` | BYTEA, NOT NULL | `SHA3-256(chunk_hash_0 \|\| … \|\| chunk_hash_n)` |
| `sign_b64` | BYTEA, NOT NULL | ML-DSA-87 signature over all other fields |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `deleted_flag` | BOOLEAN, NOT NULL, DEFAULT false | Soft delete |

**Verification**: concatenate all `file_chunks.chunk_hash` values in `chunk_index` order, compute SHA3-256, compare with `chunks_digest`. The signature covers `chunks_digest`, so chunk integrity is transitively bound to `sign_b64`.

### 7.2 `file_chunks` (Electric-synced)

One row per chunk. Not individually signed — integrity is derived from `file_blobs.chunks_digest` → `sign_b64`.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, FK → file_blobs | Parent file |
| `chunk_index` | INTEGER | 0-based position |
| `chunk_hash` | BYTEA, NOT NULL | `SHA3-256(encrypted_chunk_blob)` |
| `size` | INTEGER, NOT NULL | Encrypted chunk byte size |
| | PK | `(file_id, chunk_index)` |

Offsets are not stored — they are derivable: `offset = chunk_index * chunk_size`. The `size` column handles the last chunk being shorter.

### 7.3 `chunk_uploads` (local only, NOT Electric-synced)

Tracks uploaded chunk blobs before the signed manifest arrives. Provides ownership tracking, upload resume, and unsigned-data accounting.

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Client-provided `"fb_" + UUIDv7` |
| `chunk_index` | INTEGER | Position in file |
| `chunk_hash` | BYTEA, NOT NULL | `SHA3-256(blob)` — also its filesystem address |
| `uploader_hash` | TEXT, NOT NULL | Who uploaded this chunk |
| `size` | INTEGER, NOT NULL | Blob byte size |
| `uploaded_at` | BIGINT, NOT NULL | Unix seconds |
| | PK | `(file_id, chunk_index)` |

**Queries this table supports**:
- **Ownership**: `WHERE uploader_hash = ?` — attribute disk usage
- **Resume**: `WHERE file_id = ?` — client queries which indexes are already uploaded
- **Unsigned budget**: `SUM(size) WHERE uploader_hash = ? AND file_id NOT IN (SELECT file_id FROM file_blobs)` — uncommitted bytes per user; device rejects further uploads if exceeded
- **GC**: `WHERE uploaded_at < threshold AND file_id NOT IN (SELECT file_id FROM file_blobs)` — delete stale rows + orphan filesystem blobs

## 8. Filesystem Layout

### 8.1 Content-Addressed Storage

Chunks are stored by their hash, two-level hex sharding:

```
<drive>/chunks/<chunk_hash[0:2]>/<chunk_hash[2:4]>/<chunk_hash_full_hex>
```

Example: chunk with SHA3-256 hash `ab12cd34ef...` →

```
chunks/ab/12/ab12cd34ef56789...
```

- 256 x 256 = 65,536 leaf directories
- 4.2M chunks (4 TB file) → ~64 files per directory — well within FAT16 limits
- Linear directory scan stays fast at <100 entries per directory
- Content-addressing gives natural dedup of identical encrypted blobs

No staging directory. Uploaded chunks go directly to their content-addressed path. The `chunk_uploads` table (§7.3) tracks which blobs are uncommitted.

## 9. Upload Protocol

```
 Client                              Device
   │                                    │
   │─── GET /api/v1/challenge ─────────>│  PoP authentication
   │<── {challenge_id, challenge} ──────│
   │                                    │
   │  encrypt chunk 0, compute hash     │
   │─── PUT /files/<file_id>/0 ────────>│  PoP-authenticated, blob body
   │    device: SHA3-256(blob)           │  store at chunks/<h[0:2]>/<h[2:4]>/<h>
   │    insert into chunk_uploads        │  track ownership + file origin
   │<── 200 {chunk_hash} ──────────────│
   │                                    │
   │  encrypt chunk 1, compute hash     │
   │─── PUT /files/<file_id>/1 ────────>│  same flow
   │<── 200 {chunk_hash} ──────────────│
   │─── ...                             │  progressive encrypt + upload
   │                                    │
   │─── GET /files/<file_id>/status ───>│  resume support (optional)
   │<── [0, 1, 4, 5] ─────────────────│  uploaded chunk indexes
   │                                    │
   │  all chunks uploaded               │
   │  compute chunks_digest, sign       │
   │─── POST /electric/v1/ingest ──────>│  signed file_blobs + file_chunks rows
   │    device verifies:                │  1. sign_b64 on file_blobs
   │      chunks_digest matches          │  2. SHA3-256(all chunk_hashes) == chunks_digest
   │      every chunk_hash on disk       │  3. each blob exists on filesystem
   │<── 200 {txid} ────────────────────│  committed to Electric tables
   │                                    │  chunk_uploads rows for this file can be GC'd
```

The client encrypts and uploads chunks progressively (no need to encrypt everything upfront). After all chunks are on the device, the client computes `chunks_digest` from the chunk hashes it received, signs the `file_blobs` manifest, and commits via the standard ingest endpoint.

## 10. Sync Protocol

When Device B receives `file_blobs` + `file_chunks` rows via Electric:

1. **Verify signature** — `ML-DSA-87.verify(sign_b64, sign_pkey)` on `file_blobs` → drop if invalid
2. **Verify chunk binding** — `SHA3-256(chunk_hash_0 || … || chunk_hash_n) == chunks_digest` → drop if mismatch
3. **Download chunks** — for each `file_chunks` row where the blob is not on local filesystem:
   - Request encrypted chunk from source device (HTTP out-of-band)
   - Compute `SHA3-256(received_blob)`
   - Compare with `chunk_hash` → discard blob if mismatch
   - Write to content-addressed path: `chunks/<h[0:2]>/<h[2:4]>/<h>`
4. **File is available** once all chunks are present on local filesystem

## 11. Chunk Encryption

All encryption/decryption happens client-side (browser, Web Crypto API).

- **Algorithm**: AES-256-GCM
- **Key**: `enc_secret` — random 32 bytes, unique per file
- **Nonce**: 12 bytes — `chunk_index` zero-padded to 12 bytes (deterministic)
- **Auth tag**: 16 bytes, appended to ciphertext (standard GCM output)

```
encrypted_chunk = AES-256-GCM(enc_secret, nonce=pad(chunk_index, 12), plaintext_chunk)
chunk_hash      = SHA3-256(encrypted_chunk || auth_tag)
```

Nonce safety: `enc_secret` is unique per file (no reuse across files), `chunk_index` is unique within file (no reuse within file). The 2^32 nonce space supports files up to ~4 TB per key.

## 12. Open Questions

- **Unsigned budget**: configurable per device? Suggested default ~256 MB per user.
- **GC policy**: how long before uncommitted `chunk_uploads` entries (and their blobs) are cleaned up? Suggested: 1 hour.
- **Max file size**: hard cap? Crypto supports ~4 TB per key. Practical limit is device storage.
- **Chunk download protocol**: HTTP range requests? Dedicated endpoint? Batched transfers?
- **Partial file availability**: can a client begin downloading/decrypting before all chunks are synced to a device?

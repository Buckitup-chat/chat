# File Storage Constraints

Constraints and design considerations for storing large files on BuckitUp platform devices. Schema and implementation details TBD.

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

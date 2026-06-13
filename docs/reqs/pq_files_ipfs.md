# File Storage — IPFS Chunk Sync

> **DRAFT** — feasibility analysis, not yet implemented. Describes using IPFS as the chunk byte layer for [File Storage](pq_files.md) protocol v2. Prerequisite reading: [pq_files.md §14](pq_files.md#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes) (v2 migration plan).

## 1. Motivation

The v2 migration plan ([pq_files.md §14](pq_files.md#14-migration-plan-chunk-blobs--filesystem-protocol-v2-raw-bytes)) moves chunk bytes out of PostgreSQL onto the filesystem and introduces `ChunkFetcher` for device-to-device byte transfer. Two problems remain:

1. **Multi-peer content routing** (open question in §14.8): `ChunkFetcher` must know which peer has which chunk. Single-peer topologies can reuse the Electric shape source address, but multi-peer needs a chunk-availability mechanism that v2 leaves unresolved.
2. **USB drive portability**: when a USB drive moves between devices, its chunk bytes need to be discoverable and servable. v2's filesystem shard layout (`pq_files/<shard>/<file_id>/<chunk_index>`) requires custom import logic.

IPFS solves both: Bitswap handles multi-peer block exchange natively (any connected peer with a block serves it), and content-addressed blocks are portable by design.

## 2. Two-Layer Architecture

```
Electric (PG)                           IPFS
─────────────                           ────
files manifest                          chunk bytes (raw encrypted)
file_chunks manifest (CID, size, sig)   Bitswap (peer-to-peer transfer)
"what files exist, who owns them"       "where are the bytes, move them"

        ▼ "file available" = manifest present + all CIDs in local IPFS ▲
```

**Electric syncs**: `files` rows (manifest: chunk_count, chunk_sign_hashes, signature) + `file_chunks` rows (metadata only: CID, size, uploader_hash, signature). Small rows — no bytes in PG.

**IPFS syncs**: raw encrypted chunk bytes, identified by CID. Bitswap handles peer discovery and transfer. No `ChunkFetcher` worker needed.

**USB drives**: carry both PG data (manifests via per-drive PG instance) and IPFS blocks. A single IPFS daemon per device serves blocks from SD card and any inserted USB drives.

## 3. Tables

### 3.1 `file_chunks` (Electric-synced, v2+IPFS)

Same as [pq_files.md §14.2](pq_files.md#142-protocol-v2-changes) with `cid` added and `data_b64` removed:

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT, NOT NULL | Parent file reference |
| `chunk_index` | INTEGER, NOT NULL | 0-based position |
| `cid` | TEXT, NOT NULL | IPFS CIDv1 (SHA2-256 multihash) — block lookup key |
| `data_hash` | TEXT, NOT NULL | `"fd_" + lowercase hex SHA3-512(raw)` — trust chain verification |
| `size` | INTEGER, NOT NULL | Encrypted chunk byte size |
| `uploader_hash` | TEXT, NOT NULL | FK-like -> user_cards |
| `owner_timestamp` | BIGINT, NOT NULL | Monotonic counter |
| `sign_b64` | BYTEA, NOT NULL | Signature over `(file_id, chunk_index, data_hash, size, uploader_hash, owner_timestamp)` |
| | PK | `(file_id, chunk_index)` |

Rows are ~5 KB (dominated by ML-DSA-87 signature) — the table stays in the Electric publication.

### 3.2 `files` (unchanged)

Same as [pq_files.md §1.1](pq_files.md#11-files-electric-synced). The trust chain is unmodified: `chunk_sign_hashes[i] = SHA3-512(chunk_i.sign_b64)`.

### 3.3 `upload_chunks` (unchanged)

Same as [pq_files.md §1.3](pq_files.md#13-upload_chunks-local-only-not-electric-synced). Budget accounting uses `size` from manifest rows — unaffected by IPFS.

### 3.4 `missing_chunks` (local only, NOT Electric-synced)

Same structure as [pq_files.md §14.3](pq_files.md#143-target-architecture) with `cid` added:

| Column | Type | Description |
|---|---|---|
| `file_id` | TEXT | Parent file |
| `chunk_index` | INTEGER | Position in file |
| `cid` | TEXT, NULL | IPFS CIDv1 — NULL while `file_chunks` manifest row hasn't arrived; non-NULL = Bitswap can fetch it |
| `data_hash` | TEXT, NULL | `fd_`-prefixed hash — NULL until manifest row arrives |
| `size` | INTEGER, NULL | Expected byte size — NULL until manifest row arrives |
| `attempts` | INTEGER, DEFAULT 0 | Retry bookkeeping (for manual re-fetch if Bitswap stalls) |
| `updated_at` | BIGINT | Last attempt or creation time (TimeKeeper) |
| | PK | `(file_id, chunk_index)` |

Population follows the same two-stage pre-seed as v2 ([pq_files.md §14.3](pq_files.md#143-target-architecture)): `files` manifest arrival creates placeholders → `file_chunks` manifest rows fill `cid`, `data_hash`, `size`.

The table serves as a **UI signal** ("X of Y synced") and a **Bitswap bridge** — when `cid` is set, the chunk is added to the IPFS want-list. Bitswap handles the actual fetching. Once bytes arrive and pass verification, the `missing_chunks` row is deleted.

## 4. Hash Compatibility

Two independent hash functions, clean separation of concerns:

| Hash | Algorithm | Purpose | Stored as |
|---|---|---|---|
| `data_hash` | SHA3-512 | Trust chain — bound to ML-DSA-87 signature, verified on admission | `"fd_" + hex` in `file_chunks` |
| CID | SHA2-256 (multihash) | IPFS block routing — Bitswap exchange, blockstore lookup | CIDv1 string in `file_chunks.cid` |

On chunk admission (any source): compute `SHA3-512(raw bytes)`, verify against `data_hash` from the signed manifest. IPFS independently computes SHA2-256 for the CID. The trust chain ([pq_files.md §14.3](pq_files.md#143-target-architecture) "Receiver integrity") is unchanged — the bytes channel is untrusted by design; integrity is enforced at admission, not in transport.

## 5. Upload Protocol

Same as [pq_files.md §14.2](pq_files.md#142-protocol-v2-changes) chunk upload endpoint, with IPFS replacing filesystem storage:

```
Client                              Device
  │                                    │
  │  encrypt chunk, sign metadata      │
  │─── PUT /electric/v1/file_chunk ───>│  raw body, sig in headers
  │       /:file_id/:chunk_index       │
  │    verify signature (headers)      │
  │    stream body → temp file         │
  │    SHA3-512(body) == data_hash?    │
  │    ipfs block put → CID            │
  │    insert file_chunks (with CID)   │
  │      + upload_chunks in one txn    │
  │<── 200 {txid} ─────────────────────│
  │                                    │
  │  ... repeat for all chunks ...     │
  │                                    │
  │  build files manifest with         │
  │    chunk_sign_hashes array         │
  │─── POST /electric/v1/ingest ──────>│  files insert (unchanged)
  │<── 200 {txid} ─────────────────────│
```

Upload authentication is unchanged from v2: the chunk signature is the proof of possession — no challenge flow ([pq_files.md §14.2](pq_files.md#142-protocol-v2-changes) "Upload authentication").

## 6. Sync Protocol

When Device B receives rows via Electric:

1. **`files` row arrives** → verify ML-DSA-87 signature → store → insert `chunk_count` placeholder rows into `missing_chunks` (indices `0..chunk_count-1`, `cid = NULL`)
2. **`file_chunks` manifest rows arrive** → update matching `missing_chunks` row: fill `cid`, `data_hash`, `size` → **add CID to IPFS want-list** (Bitswap begins fetching)
3. **Bitswap delivers a block** → verify `SHA3-512(raw bytes) == data_hash` → admit block to IPFS repo → delete `missing_chunks` row
4. **File is available** once zero `missing_chunks` rows remain for that `file_id`

No `ChunkFetcher` worker. IPFS Bitswap handles peer selection, parallel fetching from multiple peers, and retry natively. The `missing_chunks` table provides the UI signal and acts as the bridge between Electric (manifest delivery) and IPFS (byte delivery).

### 6.1 Bitswap vs ChunkFetcher

| | ChunkFetcher (v2 filesystem) | Bitswap (IPFS) |
|---|---|---|
| Peer selection | Open question — must build | Native: queries all connected peers |
| Parallel fetch | Must build | Native: fetches from multiple peers simultaneously |
| Retry | Must build (attempts/backoff) | Native: want-list persistence, session management |
| Prioritization | Must build (promote requested chunks) | Configurable via want-list priorities |

## 7. Download Protocol

```
Client                              Device
  │                                    │
  │─── GET /electric/v1/shapes ───────>│  fetch files manifest (unchanged)
  │<── {chunk_count, chunk_sign_hashes}│
  │                                    │
  │  for i in 0..chunk_count-1:        │
  │─── GET /electric/v1/file_chunk ───>│  device resolves CID from manifest
  │       /:file_id/:i                 │  ipfs block get <CID>
  │<── application/octet-stream ───────│  raw bytes, x-chunk-size header
  │  verify SHA3-512(raw) == data_hash │
  │  decrypt with AES-256-GCM          │
  │  append to output                  │
```

**Implementation**: `FileChunkController.show/2` looks up the CID from the `file_chunks` manifest row, retrieves raw bytes from IPFS, serves via response stream. Compared to v2's `send_file` from filesystem, this adds one IPFS API call (`/api/v0/block/get`) but avoids maintaining a parallel filesystem shard layout.

## 8. USB Drive Integration

### 8.1 Device Model

One IPFS daemon per device. Primary blockstore on SD card. When a USB drive is inserted, its blocks become available through the same daemon — SD and USB blocks are served together.

```
Device (RPi4)
├── SD card
│   ├── IPFS daemon (single instance)
│   ├── IPFS repo / blockstore
│   └── internal PG
│
├── USB-A (inserted)
│   ├── PG data dir (manifests)
│   ├── chunk blocks → imported into IPFS repo
│   └── CubDB databases
│
└── USB-B (inserted)
    ├── PG data dir (manifests)
    ├── chunk blocks → imported into IPFS repo
    └── CubDB databases
```

### 8.2 Block Import Strategy

When a USB drive with chunk blocks is inserted:

| Strategy | Mechanism | Pro | Con |
|---|---|---|---|
| **Background import** | Scan USB for block files, `ipfs block put` each into daemon's repo | Simple, reliable; blocks persist after eject | Copies data; import time proportional to content |
| **Filestore (--nocopy)** | `ipfs add --nocopy` references files by path, zero-copy | No duplication | Experimental Kubo feature; references break on eject; files must not move |
| **Custom datastore plugin** | Go plugin adds USB path as read-only blockstore mount | Zero-copy, clean | Requires maintaining a Go plugin; Kubo plugin API is unstable |
| **Symlink farm** | Symlink USB block files into IPFS repo's blockstore directory | Zero-copy, no plugin | Fragile; IPFS blockstore layout is internal/versioned |

**Recommended starting point**: background import. It's the simplest and most reliable approach. Blocks are imported into the IPFS repo on USB insertion and persist after ejection. Optimization to filestore or custom plugin can follow if import overhead proves too high.

### 8.3 Boot Sequence Integration

The [BootSupervisor](pq_files.md) staged startup gains an IPFS-related step:

```
Healer → Mounter → InternalDbAwaiter → InitPg → PgServer → DbCreated →
  RepoStarted → MigrationsRun → IpfsImporter → Decider
```

`IpfsImporter` scans the mounted drive for block files and imports them into the device's IPFS daemon (which starts separately, on the SD card, not per drive). The import can also run as a background task after the Decider, since block availability is not required for the boot decision.

## 9. IPFS Daemon Configuration

### 9.1 Private Network

All BuckitUp IPFS nodes form a private network. No public DHT participation, no public bootstrap nodes.

```json
{
  "Bootstrap": [],
  "Routing": { "Type": "none" },
  "Swarm": {
    "ConnMgr": {
      "HighWater": 20,
      "LowWater": 5,
      "GracePeriod": "30s"
    },
    "AddrFilters": []
  },
  "Discovery": {
    "MDNS": { "Enabled": false }
  }
}
```

Plus `swarm.key` file with `LIBP2P_FORCE_PNET=1` — nodes without the key cannot connect.

Peer discovery reuses the existing infrastructure: LAN detection (`Chat.NetworkSynchronization.PeerDetection.LanDetection`) and ZeroTier overlay addresses are fed as IPFS swarm peers via `ipfs swarm connect /ip4/<addr>/tcp/4001/p2p/<peer_id>`.

### 9.2 Resource Limits (RPi4)

| Parameter | Value | Rationale |
|---|---|---|
| `ConnMgr.HighWater` | 20 | Limit concurrent connections (small private network) |
| `ConnMgr.LowWater` | 5 | Keep a few persistent connections |
| `Datastore` | flatfs | Filesystem-backed, no in-memory index overhead |
| Disable: relay, NAT traversal, mDNS | — | Use BuckitUp's own peer discovery |

**Expected RAM**: 30-60 MB idle, 80-200 MB under active Bitswap transfer. Within budget on 4GB RPi4 (PG ~100-300MB, BEAM ~200-500MB, OS+misc ~100-200MB).

### 9.3 Daemon Management

Follows `Platform.Storage.Pg.Daemon` pattern: `GracefulGenServer` + `MuonTrap.Daemon`, staged readiness polling.

```
Platform.Supervisor
├── Platform.Storage.Ipfs.Daemon   ← starts on boot, repo on SD card
│     MuonTrap.Daemon: /usr/bin/ipfs daemon --routing=none --migrate
│     readiness: poll `ipfs id` until it returns
│
├── Platform.Drives (DynamicSupervisor)
│   ├── BootSupervisor (per USB)
│   │   ├── ... existing stages ...
│   │   ├── IpfsImporter           ← imports USB blocks into the daemon
│   │   └── Decider
```

The IPFS daemon is device-scoped (not per-drive), so it starts under the main supervisor, not inside the per-drive BootSupervisor.

### 9.4 Kubo Deployment

| Option | Mechanism | Trade-off |
|---|---|---|
| **Pre-built binary** | aarch64 Kubo binary in `bktp_rpi4/configs/rootfs_overlay/usr/bin/ipfs` | Simple; matches ZeroTier pattern; must manually update |
| **Buildroot package** | Custom `.mk` file using Go toolchain (available in `bktp_rpi4/buildroot-2025.11/package/go/`) | Proper; reproducible; +10-30 min build time |

## 10. Garbage Collection

BuckitUp GC ([pq_files.md §8](pq_files.md#8-garbage-collection)) must coordinate with IPFS:

1. **Deleted files**: when `files.deleted_flag = true`, GC deletes `file_chunks` manifest rows AND calls `ipfs block rm <CID>` for each chunk (or `ipfs pin rm` if using pinning)
2. **Stale uploads**: same as v2 — `upload_chunks` older than 2 days are deleted, corresponding `file_chunks` rows removed, IPFS blocks removed
3. **IPFS repo GC**: periodic `ipfs repo gc` to reclaim unpinned blocks. Must run AFTER BuckitUp GC removes references, not concurrently.

**Orphan blocks**: if a PG transaction rolls back after `ipfs block put`, the block has no manifest row. BuckitUp GC sweeps blocks with no matching `file_chunks` row (same 2-day grace period as v2 orphan files).

## 11. Security

Encrypted chunks are opaque blobs — IPFS stores and transfers them without content knowledge.

| Concern | Assessment |
|---|---|
| CID content identity | Same CID = same content. But each file uses unique `enc_secret`, so identical plaintext → different ciphertext → different CIDs. Non-issue. |
| Private network | Swarm key ensures only BuckitUp devices join. Without it, chunks are discoverable on public DHT (harmless since encrypted, but leaks metadata). |
| Bitswap want-lists | Reveal which chunks a device seeks. Acceptable in a small private network of trusted BuckitUp devices — peers already know about each other via Electric. |
| Block probing | `ipfs block stat <CID>` can check presence without auth. Same threat model as v2's unauthenticated `GET /file_chunk` (returns encrypted blobs). |

No new security concerns beyond operational complexity. The encrypted-chunk model is well-suited to IPFS.

## 12. Expected Gains

Per 100 MB upload (26 chunks):

| | v1 (PG + base64) | v2 (filesystem) | v2 + IPFS |
|---|---|---|---|
| Bytes on the wire (upload) | ~133 MB | 100 MB | 100 MB |
| Device bytes written | ~270 MB (heap+TOAST+WAL) | 100 MB (raw file) | 100 MB (IPFS block) |
| WAL burst | ~133 MB | ~130 KB (manifests) | ~130 KB (manifests) |
| Multi-peer fetch | N/A (single device) | Must build | Bitswap (native) |
| USB portability | N/A | Custom import | Content-addressed import |

Write performance for chunks is comparable between v2 filesystem and IPFS — both write raw bytes to disk. IPFS adds a small overhead for CID computation (SHA2-256) and blockstore indexing.

## 13. Codebase Changes Summary

### New modules

| Module | Location | Purpose |
|---|---|---|
| `Platform.Storage.Ipfs.Daemon` | `platform/lib/platform/storage/ipfs/daemon.ex` | MuonTrap.Daemon for Kubo |
| `Platform.Storage.Ipfs.Config` | `platform/lib/platform/storage/ipfs/config.ex` | Private network config, swarm key, resource limits |
| `Platform.Storage.Ipfs.Swarm` | `platform/lib/platform/storage/ipfs/swarm.ex` | Feed LAN/ZeroTier addresses as IPFS multiaddrs |
| `Platform.Storage.Ipfs.Importer` | `platform/lib/platform/storage/ipfs/importer.ex` | USB insertion → scan + import blocks |
| `Platform.Emulator.Drive.IpfsDaemon` | `platform/lib/platform/emulator/drive/ipfs_daemon.ex` | Host-mode bypass |
| `Chat.Data.File.IpfsStore` | `chat/lib/chat/data/file/ipfs_store.ex` | Elixir HTTP client for IPFS API |

### Modified modules

| Module | Change |
|---|---|
| `Chat.Data.Schemas.FileChunk` | Add `cid` TEXT; drop `data_b64` |
| `ChatWeb.FileChunkController` | Serve from IPFS (`ipfs block get`) |
| Chunk upload endpoint | `ipfs block put` after signature verification |
| `Chat.Data.File.GC` | Also `ipfs block rm` on deletion |
| `Chat.Data.Shapes.FileChunk` | Handle `cid` in sync; bridge to IPFS want-list |
| `Platform.App.Drive.BootSupervisor` | Add `IpfsImporter` stage |
| `bktp_rpi4` defconfig | Add Kubo binary |

### Eliminated (vs v2 filesystem)

| Component | Replaced by |
|---|---|
| `ChunkStore` (filesystem sharding) | IPFS blockstore |
| `ChunkFetcher` worker | IPFS Bitswap |
| Multi-peer addressing (open question) | Bitswap (native) |

## 14. Open Questions

- **USB block serving strategy**: background import (copies, reliable) vs filestore `--nocopy` (zero-copy, fragile on eject) vs custom datastore plugin. Needs prototyping on real hardware.
- **GC coordination**: pin/unpin workflow between BuckitUp GC and IPFS repo GC. Must prevent IPFS from collecting referenced blocks or retaining deleted ones.
- **Kubo deployment**: Buildroot Go package vs pre-built aarch64 binary in rootfs overlay.
- **Resource budget**: Kubo + PG + BEAM on 4GB RPi4 under concurrent uploads + Electric sync + chat. Needs benchmarking.
- **Swarm key distribution**: baked into firmware? Shared during device pairing? Per-deployment key?
- **CargoSync adaptation**: existing CargoSync copies CubDB data for offline portable transfers. With IPFS, cargo drives carry blocks — Decider/scenario model may need updating. Does CargoSync remain for CubDB, with IPFS handling chunk bytes separately?

## 15. Recommended Next Steps

1. **Prototype Kubo on RPi4**: pre-built aarch64 binary + MuonTrap.Daemon, private network mode, measure idle/active RAM and CPU
2. **Benchmark `ipfs block put`**: 4MB encrypted blocks on USB/SD storage, compare throughput vs raw `File.write`
3. **Test USB block import**: measure import speed for a USB with 100 chunk files, try filestore `--nocopy` vs full import
4. **Spike the bridge**: Electric manifest arrival → IPFS want-list, verify Bitswap fetches blocks between two RPi4s on LAN
5. **Design migration**: from v1 (PG+base64) to v2+IPFS — schema changes, data truncation (PoC stage), client updates

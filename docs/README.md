# Chat Documentation

Two generations of the encryption/storage stack are documented separately:

- **[`trusted/`](./trusted/)** — the current production system: server-side ECC encryption over CubDB.
- **[`pq/`](./pq/)** — in development: frontend post-quantum encryption over Electric SQL + Postgres. (`pq` is already the naming convention used throughout `lib/enigma_pq/`, and `trusted` matches the existing `/trusted` LiveView route that the legacy client now lives behind.)

Anything not tied to either generation stays at the top level, under `proposal/`.

## trusted/ — server ECC + CubDB

### Architecture
Internal design of storage, supervision, and cryptography.

- [Encryption](./trusted/architecture/encryption.livemd) — ECDH / Blowfish / ECDSA / Shamir
- [DB structure](./trusted/architecture/db_structures.livemd) — CubDB key-value layout
- [AdminDB structure](./trusted/architecture/admin_db_structures.livemd) — system-config DB
- [DB Prioritization](./trusted/architecture/prioritization.livemd) — write queue & priorities
- [Supervision](./trusted/architecture/supervision.livemd) — DB and device supervision tree

### Flows
End-to-end scenarios across the app.

- [Room approval flow](./trusted/flows/approve_flow.livemd)
- [Naive API file upload](./trusted/flows/upload_files.livemd)
- [Cargo scenario](./trusted/flows/cargo_scenario.livemd)
- [Cargo options](./trusted/flows/cargo_options.livemd)
- [Cargo bench](./trusted/flows/cargo-bench.livemd)

### Proposals
Design sketches — may or may not be implemented.

- [Data flow](./trusted/proposal/data_flow.livemd)
- [Handshake flow](./trusted/proposal/handshake_flow.livemd)
- [User data](./trusted/proposal/user_data.livemd)

## pq/ — frontend post-quantum + Electric/Postgres

### Electric SQL
Real-time sync layer built on Phoenix.Sync + ElectricSQL.

- [Electric abstraction layer](./pq/electric/Electric_Abstraction_Layer.md)
- [PQ invariants](./pq/invariants/README.md)

### Flows
- [PQ optical handshake](./pq/flows/pq_optical-handshake.livemd)

### Proposals
- [External frontend integration](./pq/proposal/external_frontend_integration.md)
- [Reviews](./pq/proposal/reviews.md)

### Requirements
Hard requirements and specs. See [`pq/reqs/CLAUDE.md`](./pq/reqs/CLAUDE.md) for the folder's topic/status convention.

- [Cross-server data integrity](./pq/reqs/cross-server-data-integrity.livemd)
- [Electric API sandbox user](./pq/reqs/electric_api_sandbox_user.md)
- [Electric network sync](./pq/reqs/electric_network_sync.md)
- [Electric proof-of-possession](./pq/reqs/electric-proof-of-possesion.md)
- [Electric shape behaviours](./pq/reqs/electric_shape_behaviours.md)
- [PostgreSQL constraints](./pq/reqs/pg_constraints.md)
- [PQ dialogs](./pq/reqs/pq_dialogs.md)
- [PQ user](./pq/reqs/pq_user.md)
- [PQ user storage](./pq/reqs/pq_user_storage.md)
- [PQ files](./pq/reqs/files/pq_files.done.md)
- [PQ chunk writer](./pq/reqs/files/pq_chunk_writer.done.md)
- [PQ video streaming](./pq/reqs/pq_video_streaming.md)

## proposal/ — generation-agnostic

- [Device WebRTC](./proposal/device_webrtc.md)
- [Telegram notifications](./proposal/telegram_notifications.md)

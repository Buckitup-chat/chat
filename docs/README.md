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

### Invariants
- [PQ invariants overview](./pq/invariants/README.md)
- [Proof-of-Possession](./pq/invariants/01_proof_of_possession.md)
- [Integrity](./pq/invariants/02_integrity.md)
- [Data Versioning](./pq/invariants/03_data_versioning.md)
- [Ordering](./pq/invariants/04_ordering.md)
- [Content Polymorphism](./pq/invariants/07_content_polymorphism.md)
- [Snapshots](./pq/invariants/08_snapshots.md)
- [Symmetric Key Derivation](./pq/invariants/09_symmetric_keys.md)

### Dev
- [Database schemas](./pq/dev/SCHEMAS.md)

### Flows
- [PQ optical handshake](./pq/flows/pq_optical-handshake.livemd)

### Proposals
- [External frontend integration](./pq/proposal/external_frontend_integration.md)

### Requirements
Hard requirements and specs. See [`pq/reqs/CLAUDE.md`](./pq/reqs/CLAUDE.md) for the folder's topic/status convention.

- [Electric sandboxes](./pq/reqs/electric_sandboxes.done.md)
- [Electric network sync](./pq/reqs/electric_network_sync.done.md)
- [Electric shape behaviours](./pq/reqs/electric_shape_behaviours.done.md)
- [PostgreSQL constraints](./pq/reqs/pg_constraints.md)
- [PQ dialogs](./pq/reqs/pq_dialogs.done.md)
- [PQ user](./pq/reqs/pq_user.done.md)
- [PQ user storage](./pq/reqs/pq_user_storage.done.md)
- [PQ access gating](./pq/reqs/pq_access_gating.in_progress.md)
- [PQ vouch tokens](./pq/reqs/pq_vouch_tokens.in_progress.md)
- [PQ ingest conflict ownership](./pq/reqs/pq_ingest_conflict_ownership.done.md)
- [PQ integrity checker](./pq/reqs/pq_integrity_checker.proposed.md)
- [PQ recovery shares](./pq/reqs/pq_recovery_shares.proposed.md)

#### Files
- [PQ files](./pq/reqs/files/pq_files.done.md)
- [PQ chunk writer](./pq/reqs/files/pq_chunk_writer.done.md)
- [PQ video streaming](./pq/reqs/files/pq_video_streaming.done.md)

#### Reviews
- [PQ reviews](./pq/reqs/reviews/pq_reviews.in_progress.md)
- [PQ origin](./pq/reqs/reviews/pq_origin.done.md)
- [PQ review contacts](./pq/reqs/reviews/pq_review_contacts.done.md)
- [PQ review moderation](./pq/reqs/reviews/pq_review_moderation.done.md)
- [PQ review versioning](./pq/reqs/reviews/pq_review_versioning.done.md)
- [PQ review write tokens](./pq/reqs/reviews/pq_review_write_tokens.proposed.md)

## proposal/ — generation-agnostic

- [Device WebRTC](./proposal/device_webrtc.md)
- [Telegram notifications](./proposal/telegram_notifications.md)

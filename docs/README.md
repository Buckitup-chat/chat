# Chat Documentation

## Architecture
Internal design of storage, supervision, and cryptography.

- [Encryption](./architecture/encryption.livemd) — ECDH / Blowfish / ECDSA / Shamir
- [DB structure](./architecture/db_structures.livemd) — CubDB key-value layout
- [AdminDB structure](./architecture/admin_db_structures.livemd) — system-config DB
- [DB Prioritization](./architecture/prioritization.livemd) — write queue & priorities
- [Supervision](./architecture/supervision.livemd) — DB and device supervision tree

## Flows
End-to-end scenarios across the app.

- [Room approval flow](./flows/approve_flow.livemd)
- [Naive API file upload](./flows/upload_files.livemd)
- [Cargo scenario](./flows/cargo_scenario.livemd)
- [Cargo options](./flows/cargo_options.livemd)
- [Cargo bench](./flows/cargo-bench.livemd)
- [PQ optical handshake](./flows/pq_optical-handshake.livemd)

## Electric SQL
Real-time sync layer built on Phoenix.Sync + ElectricSQL.

- [Electric abstraction layer](./electric/Electric_Abstraction_Layer.md)
- [PQ data layer](./electric/pq_data_layer/README.md) · [schemas](./electric/pq_data_layer/SCHEMAS.md)

## Proposals
Design sketches — may or may not be implemented.

- [Data flow](./proposal/data_flow.livemd)
- [Handshake flow](./proposal/handshake_flow.livemd)
- [User data](./proposal/user_data.livemd)
- [Device WebRTC](./proposal/device_webrtc.md)
- [Telegram notifications](./proposal/telegram_notifications.md)

## Requirements
Hard requirements and specs.

- [Cross-server data integrity](./reqs/cross-server-data-integrity.livemd)
- [Electric API sandbox user](./reqs/electric_api_sandbox_user.md)
- [Electric network sync](./reqs/electric_network_sync.md)
- [Electric proof-of-possession](./reqs/electric-proof-of-possesion.md)
- [PQ dialogs](./reqs/pq_dialogs.md)
- [PQ user](./reqs/pq_user.md)
- [PQ user storage](./reqs/pq_user_storage.md)

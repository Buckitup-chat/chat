# User Storage Specification

## 1. Overview

User Storage is a user-scoped key-value storage system that provides encrypted, per-user data persistence synchronized via Electric shapes. The system enables authenticated users to store arbitrary encrypted data accessible through a public read, authenticated write model.

**Schema Definition**: See [pq_user.done.md](./pq_user.done.md) for complete schema details.

## 2. Core Concepts

### 2.1 Architecture
- **Storage Model**: Key-value store scoped by user_hash
- **Synchronization**: Electric shapes for real-time sync
- **Security Model**: Public reads, authenticated writes via Proof-of-Possession (PoP)
- **Encryption**: Client-side encryption; server stores values as opaque blobs
- **Versioning**: Archive-on-update — previous versions move to `user_storage_versions`

### 2.2 Key Characteristics
- **UUID Generation**: Client-side responsibility
- **Value Encryption**: Client-side encryption required
- **Conflict Resolution**: Last write wins (LWW) via `owner_timestamp`
- **Deletion Strategy**: Soft deletes via `deleted_flag`
- **Value Size Limit**: 10 MB maximum per value
- **Access Control**: Any user can read any storage (read public), only owner can write (via PoP)
- **Signature Hashing**: `sign_hash` is server-derived from `sign_b64` via `EnigmaPq.hash/1`, not client-provided

## 3. Requirements

### 3.1 Functional Requirements

**FR-1**: User MUST be able to create and update key-value pairs in their storage
**FR-2**: All write operations MUST be authenticated via Proof-of-Possession
**FR-3**: Read operations MUST NOT require authentication
**FR-4**: System MUST support batch operations (multiple mutations in single request)
**FR-5**: System MUST expose user storage and versions via Electric shapes
**FR-6**: Users MUST be able to list all their keys
**FR-7**: Client MUST encrypt values before storage
**FR-8**: System MUST archive previous versions on update (version chain via `parent_sign_hash`)
**FR-9**: System MUST verify data integrity via `Signable` protocol

### 3.2 Non-Functional Requirements

**NFR-1**: Value size MUST NOT exceed 10 MB
**NFR-2**: System MUST verify user_hash corresponds to sign_pkey
**NFR-3**: System MUST verify challenge signature with sign_skey
**NFR-4**: Server MUST store encrypted values as-is without modification
**NFR-5**: Single challenge PoP MUST suffice for batch writes to one user storage

## 4. Security Model

### 4.1 Authentication Flow

**Write Operations**:
1. Client obtains a challenge from `GET /electric/challenge`
2. Client signs challenge with sign_skey
3. Challenge + signature are injected by [`ChatWeb.Plugs.ElectricChallengeInjector`](../../../lib/chat_web/plugs/electric_challenge_injector.ex)
4. Server verifies via [`user_storage_allowed/2`](../../../lib/chat/data/user/validation.ex):
   - user_hash → UserCard lookup → `sign_pkey`
   - `EnigmaPq.verify(challenge, signature, sign_pkey)`

**Read Operations**:
- No authentication required
- Public read access to all user storage
- Privacy protected via client-side encryption

### 4.2 Proof-of-Possession (PoP)

PoP mechanism follows the same protocol as UserCards system.

**Reference**: See [electric-proof-of-possesion.md](./electric-proof-of-possesion.md) for complete PoP protocol details.

### 4.3 Signature Integrity

Each mutation carries an ML-DSA-87 signature (`sign_b64`) over its fields. The server:
1. Derives `sign_hash` from `sign_b64` via [`sync_derive_fields/1`](../../../lib/chat/data/shapes/user_storage.ex)
2. Verifies the signature via the [`Signable`](../../../lib/chat/data/integrity.ex) protocol implementation in [`UserStorage`](../../../lib/chat/data/schemas/user_storage.ex)
3. Signable fields: all schema fields except `sign_b64`, `sign_hash`, `parent_version`, `__meta__`

## 5. API Specification

### 5.1 Read Operations (Electric Shapes)

User storage is exposed via Electric shapes. The primary endpoint supports per-user filtering; a deprecated legacy endpoint provides full-table sync.

#### 5.1.1 Client-Controlled Shapes (v1) — Primary

**Endpoint**: `GET /electric/v1/shapes`

Router ([`router.ex:233-239`](../../../lib/chat_web/router.ex#L233)):
```elixir
scope "/electric/v1/shapes" do
  pipe_through [:electric]
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricTableGuard
  forward "/", ChatWeb.Plugs.HexToBase64Electric
end
```

Clients pass `table`, `where`, `columns` as query params. Per-user filtering is achieved via `where=user_hash=u_...` — this is the bandwidth-optimized path for single-user queries. The [`ElectricTableGuard`](../../../lib/chat_web/plugs/electric_table_guard.ex) plug restricts which tables are accessible.

#### 5.1.2 Legacy Sync (Phoenix.Sync) — Deprecated

**Deprecated** in favor of v1/shapes.

**Endpoint**: `GET /electric/user_storage`

Router ([`router.ex:204`](../../../lib/chat_web/router.ex#L204)):
```elixir
sync("/user_storage", Chat.Data.Schemas.UserStorage)
```

Full table sync — no server-side filtering, client must filter by `user_hash` locally. Versions exposed separately at `GET /electric/user_storage_version` ([`router.ex:205`](../../../lib/chat_web/router.ex#L205)).

### 5.2 Write Operations (Ingest Endpoint)

Write operations (insert, update) use the centralized ingest endpoint. Delete is not supported via ingest — use `deleted_flag` for soft deletes.

**Endpoint**: `POST /electric/ingest`

**Alternative**: `POST /electric/ingest_each` (processes mutations individually instead of as a batch)

Router ([`router.ex:226-227`](../../../lib/chat_web/router.ex#L226)):
```elixir
post "/ingest", ElectricController, :ingest
post "/ingest_each", ElectricController, :ingest_each
```

**Authentication**: Challenge and signature are injected by [`ElectricChallengeInjector`](../../../lib/chat_web/plugs/electric_challenge_injector.ex) plug (from headers/cookies), not from the request body.

**Request Format**:
```json
{
  "mutations": [
    {
      "table": "user_storage",
      "operation": "insert",
      "data": {
        "user_hash": "u_a3f2b9c4d5e6f789...",
        "uuid": "<uuid>",
        "value_b64": "<base64_encoded_encrypted_blob>",
        "parent_sign_hash": "uss_...",
        "owner_timestamp": 1234567890,
        "sign_b64": "<base64_signature>",
        "deleted_flag": false
      }
    }
  ]
}
```

**Note**: `sign_hash` is not sent by the client — it is derived server-side from `sign_b64`.

**Operations**: `insert`, `update`

**Batch Operations**: Multiple mutations supported in single request (via `/ingest`). Per-mutation processing available via `/ingest_each`.

**Writer Configuration** ([`ingest_configure_writer/2`](../../../lib/chat/data/shapes/user_storage.ex)):
```elixir
Writer.allow(writer, UserStorage,
  accept: [:insert, :update],
  check: &Validation.user_storage_allowed(&1, user_pop_context),
  validate: &Validation.user_storage_validate_with_versioning/3,
  insert: [pre_apply: &Validation.user_storage_pre_apply_versioning/3],
  update: [pre_apply: &Validation.user_storage_pre_apply_versioning/3]
)
```

#### 5.2.1 Response Codes

**Success (200)**:
```json
{
  "txid": "<transaction_id>"
}
```

**Error Responses**:

| Status | Condition | Description |
|--------|-----------|-------------|
| 400 | Invalid payload | Value > 10MB, missing fields, malformed data |
| 401 | PoP verification failed | Invalid signature, expired challenge |
| 409 | Conflict | UUID collision on insert |
| 422 | Validation failed | Ecto changeset errors |

#### 5.2.2 Request Validation

**Required Fields (insert)**:
- `mutations[].table`: Must be "user_storage"
- `mutations[].operation`: One of: `insert`, `update`
- `mutations[].data.user_hash`: URL-friendly hex string with "u_" prefix (130 chars)
- `mutations[].data.uuid`: Client-generated UUID
- `mutations[].data.value_b64`: Base64-encoded encrypted blob
- `mutations[].data.owner_timestamp`: Monotonic timestamp for conflict resolution
- `mutations[].data.sign_b64`: ML-DSA-87 signature for integrity verification
- `mutations[].data.deleted_flag`: Soft delete flag (boolean)

**Required Fields (update)**:
- `mutations[].data.owner_timestamp`
- `mutations[].data.sign_b64`
- `mutations[].data.sign_hash` (derived server-side, but required in changeset)

**Derived Fields** (server computes, client does not send):
- `sign_hash`: Computed from `sign_b64` via `EnigmaPq.hash/1`, prefixed with "uss_"
- `parent_sign_hash`: Set to existing record's `sign_hash` during versioning

**Constraints**:
- Value size ≤ 10 MB (before base64 encoding)
- All mutations in batch must target same user_hash
- Signature must verify against the owner's `sign_pkey`

## 6. Data Model

### 6.1 Primary Table: `user_storage`

Schema: [`Chat.Data.Schemas.UserStorage`](../../../lib/chat/data/schemas/user_storage.ex)

| Field | DB Type | Ecto Type | Notes |
|-------|---------|-----------|-------|
| `user_hash` | text | `UserHash` | PK part 1, FK → `user_cards(user_hash)`, CHECK `^u_[a-f0-9]{128}$` |
| `uuid` | uuid | `Ecto.UUID` | PK part 2, client-generated |
| `value_b64` | bytea | `:binary` | Encrypted blob, ≤10 MB |
| `sign_hash` | text | `UserStorageSignHash` | Server-derived, CHECK `^uss_[a-f0-9]{128}$` |
| `parent_sign_hash` | text | `UserStorageSignHash` | FK → `user_storage_versions(user_hash, uuid, sign_hash)`, nullable |
| `owner_timestamp` | bigint | `:integer` | Monotonic counter for conflict resolution |
| `sign_b64` | bytea | `:binary` | ML-DSA-87 signature |
| `deleted_flag` | boolean | `:boolean` | Soft delete marker |

**Primary Key**: `(user_hash, uuid)`

**Foreign Keys**:
- `user_storage_user_hash_fkey`: `user_hash` → `user_cards(user_hash)` ON DELETE CASCADE
- `user_storage_parent_sign_hash_fkey`: `(user_hash, uuid, parent_sign_hash)` → `user_storage_versions(user_hash, uuid, sign_hash)` ON DELETE RESTRICT

### 6.2 Versions Table: `user_storage_versions`

Schema: [`Chat.Data.Schemas.UserStorageVersion`](../../../lib/chat/data/schemas/user_storage_version.ex)

| Field | DB Type | Ecto Type | Notes |
|-------|---------|-----------|-------|
| `user_hash` | text | `UserHash` | PK part 1, FK → `user_cards(user_hash)` |
| `uuid` | uuid | `Ecto.UUID` | PK part 2 |
| `sign_hash` | text | `UserStorageSignHash` | PK part 3, CHECK `^uss_[a-f0-9]{128}$` |
| `value_b64` | bytea | `:binary` | Archived encrypted blob |
| `deleted_flag` | boolean | `:boolean` | Archived delete marker |
| `parent_sign_hash` | text | `UserStorageSignHash` | FK → self `(user_hash, uuid, sign_hash)`, nullable |
| `owner_timestamp` | bigint | `:integer` | Archived timestamp |
| `sign_b64` | bytea | `:binary` | Archived signature |

**Primary Key**: `(user_hash, uuid, sign_hash)`

**Foreign Keys**:
- `user_storage_versions_user_hash_fkey`: `user_hash` → `user_cards(user_hash)` ON DELETE CASCADE
- `user_storage_versions_parent_sign_hash_fkey`: `(user_hash, uuid, parent_sign_hash)` → `user_storage_versions(user_hash, uuid, sign_hash)` ON DELETE RESTRICT

**Indexes**:
- Index on `parent_sign_hash` for version chain traversal

**PostgreSQL Publication**:
- Both `user_storage` and `user_storage_versions` added to `electric_publication_default`

### 6.3 Custom Types

- [`Chat.Data.Types.UserStorageSignHash`](../../../lib/chat/data/types/user_storage_sign_hash.ex) — prefixed hash type using `PrefixedHash` with prefix `"uss_"` (from [`Consts.user_storage_sign_prefix/0`](../../../lib/chat/data/types/consts.ex))

## 7. Versioning

### 7.1 Architecture

When a `user_storage` record is updated, the old version is archived to `user_storage_versions` and the new version replaces it. This creates a linked chain via `parent_sign_hash`.

Implementation: [`Chat.Data.User.Versioning`](../../../lib/chat/data/user/versioning.ex)

### 7.2 Conflict Resolution

Both insert-with-conflict and update paths compare `owner_timestamp`:

- **New timestamp > existing**: archive existing to versions, apply new to main table
- **New timestamp ≤ existing**: archive incoming to versions, keep existing in main table

This ensures the main table always holds the latest version regardless of arrival order.

### 7.3 Dual Pipeline

Versioning is used by both ingestion paths:

1. **HTTP ingestion** (`ElectricController`): via `user_storage_validate_with_versioning/3` and `user_storage_pre_apply_versioning/3` in [`Validation`](../../../lib/chat/data/user/validation.ex)
2. **Electric sync** (`ShapeWriter`): via `sync_persist/2` in [`Shapes.UserStorage`](../../../lib/chat/data/shapes/user_storage.ex), calling [`User.update_storage_with_versioning/2`](../../../lib/chat/data/user.ex) and [`User.insert_storage_with_conflict/2`](../../../lib/chat/data/user.ex)

### 7.4 Protocols

- **`TimestampedData`** protocol: implemented for `UserStorage`, returns `owner_timestamp` for timestamp comparison
- **`Signable`** protocol: implemented for `UserStorage`, provides fields/key/signature for integrity verification

## 8. Implementation Details

### 8.1 Key Source Files

| Component | File |
|-----------|------|
| Schema (main) | [`lib/chat/data/schemas/user_storage.ex`](../../../lib/chat/data/schemas/user_storage.ex) |
| Schema (versions) | [`lib/chat/data/schemas/user_storage_version.ex`](../../../lib/chat/data/schemas/user_storage_version.ex) |
| Shape behaviour | [`lib/chat/data/shapes/user_storage.ex`](../../../lib/chat/data/shapes/user_storage.ex) |
| Versioning logic | [`lib/chat/data/user/versioning.ex`](../../../lib/chat/data/user/versioning.ex) |
| Validation | [`lib/chat/data/user/validation.ex`](../../../lib/chat/data/user/validation.ex) |
| User data operations | [`lib/chat/data/user.ex`](../../../lib/chat/data/user.ex) |
| Custom type (sign_hash) | [`lib/chat/data/types/user_storage_sign_hash.ex`](../../../lib/chat/data/types/user_storage_sign_hash.ex) |
| Ingest controller | [`lib/chat_web/controllers/electric_controller.ex`](../../../lib/chat_web/controllers/electric_controller.ex) |
| Router (sync + ingest) | [`lib/chat_web/router.ex`](../../../lib/chat_web/router.ex) |
| PoP protocol | [electric-proof-of-possesion.md](./electric-proof-of-possesion.md) |

### 8.2 Migrations

| Migration | Purpose |
|-----------|---------|
| `20260205000003` | Create `user_storage` table |
| `20260220052309` | Add to Electric publication |
| `20260221083609` | Drop timestamps |
| `20260223105135` | Rename `value` → `value_b64` |
| `20260321210327` | Add versioning fields + `user_storage_versions` table |
| `20260321210608` | Add `user_storage_versions` to Electric publication |
| `20260324074642` | Convert hashes from domain/bytea to text + CHECK constraints |
| `20260822101214` | Self-referential FK on `user_storage_versions.parent_sign_hash` |

### 8.3 Data Encoding

**Field Encoding**:
- `user_hash`: Text with "u_" prefix (e.g., "u_a3f2b9c4d5e6f789...")
- `sign_hash`: Text with "uss_" prefix (e.g., "uss_9f86d081884c7d65...")
- `parent_sign_hash`: Text with "uss_" prefix or null
- `value_b64`: Binary (bytea) — base64-encoded by client before sending
- `sign_b64`: Binary (bytea) — base64-encoded ML-DSA-87 signature
- Hex-encoded fields are decoded by [`HexToBase64Electric`](../../../lib/chat_web/plugs/hex_to_base64_electric.ex) plug on the v1 shapes path

## 9. Client Responsibilities

### 9.1 Encryption
- Client MUST encrypt values before sending to server
- Server stores encrypted blobs without decryption
- Encryption ensures privacy despite public read access

### 9.2 UUID Management
- Client MUST generate UUIDs for new storage entries
- Client MUST track UUID-to-key mapping locally
- Client MUST handle UUID conflicts (409 responses)

### 9.3 Key Listing
- Client implements key listing via shape data filtering
- All user's storage entries available through shape subscription
- Per-user filtering via `where=user_hash=u_...` on v1/shapes endpoint

### 9.4 Signature
- Client MUST sign mutations with ML-DSA-87 using `sign_skey`
- Client does NOT send `sign_hash` — server derives it from `sign_b64`

## 10. References

### 10.1 Electric Documentation
- [Electric Shapes Guide](https://electric-sql.com/docs/guides/shapes) - Core concepts and where clause filtering
- [Electric HTTP API](https://electric-sql.com/openapi) - REST API reference
- [Phoenix.Sync Documentation](https://hexdocs.pm/phoenix_sync/) - Phoenix integration
- [Phoenix Integration Guide](https://electric-sql.com/docs/integrations/phoenix) - Electric + Phoenix setup

### 10.2 Related Specifications
- [pq_user.done.md](./pq_user.done.md) - User schema definition (parent of user_storage)
- [electric-proof-of-possesion.md](./electric-proof-of-possesion.md) - PoP authentication protocol

# User Storage Specification

## 1. Overview

User Storage is a user-scoped key-value storage system that provides encrypted, per-user data persistence synchronized via Electric shapes. The system enables authenticated users to store arbitrary encrypted data accessible through a public read, authenticated write model.

**Schema Definition**: See [pq_user.md](./pq_user.md) for complete schema details.

## 2. Core Concepts

### 2.1 Architecture
- **Storage Model**: Key-value store scoped by user_hash
- **Synchronization**: Electric shapes for real-time sync
- **Security Model**: Public reads, authenticated writes via Proof-of-Possession (PoP)
- **Encryption**: Client-side encryption; server stores values as opaque blobs

### 2.2 Key Characteristics
- **UUID Generation**: Client-side responsibility
- **Value Encryption**: Client-side encryption required
- **Conflict Resolution**: Last write wins (LWW)
- **Deletion Strategy**: Hard deletes
- **Timestamps**: Not used
- **Value Size Limit**: 10 MB maximum per value
- **Access Control**: Any user can read any storage (read public), only owner can write (via PoP)

## 3. Requirements

### 3.1 Functional Requirements

**FR-1**: User MUST be able to create, update, and delete key-value pairs in their storage
**FR-2**: All write operations MUST be authenticated via Proof-of-Possession
**FR-3**: Read operations MUST NOT require authentication
**FR-4**: System MUST support batch operations (multiple mutations in single request)
**FR-5**: System MUST expose user storage via Electric shapes
**FR-6**: Users MUST be able to list all their keys
**FR-7**: Client MUST encrypt values before storage

### 3.2 Non-Functional Requirements

**NFR-1**: Value size MUST NOT exceed 10 MB
**NFR-2**: System MUST verify user_hash corresponds to sign_pkey
**NFR-3**: System MUST verify challenge signature with sign_skey
**NFR-4**: Server MUST store encrypted values as-is without modification
**NFR-5**: Single challenge PoP MUST suffice for batch writes to one user storage

## 4. Security Model

### 4.1 Authentication Flow

**Write Operations**:
1. Client generates challenge via PoP protocol
2. Client signs challenge with sign_skey
3. Server verifies:
   - user_hash corresponds to sign_pkey
   - challenge signature is valid
   - user exists in system

**Read Operations**:
- No authentication required
- Public read access to all user storage
- Privacy protected via client-side encryption

### 4.2 Proof-of-Possession (PoP)

PoP mechanism follows the same protocol as UserCards system.

**Reference**: See [electric-proof-of-possesion.md](./electric-proof-of-possesion.md) for complete PoP protocol details.

## 5. API Specification

### 5.1 Read Operations (Electric Shapes)

User storage is exposed via Electric shapes with two supported patterns:

#### 5.1.1 Option 1: Filtered Shape (Bandwidth Optimized)

**Endpoint**: `GET /electric/v1/user_storage/{user_hash}`

**Query Parameters**:
- `user_hash`: Base64-encoded user hash

**Router Configuration**:
```elixir
sync "/user_storage/:user_hash", Chat.Data.Schemas.UserStorage,
  where: "user_hash = :user_hash"
```

**Client Request Example**:
```
GET /electric/v1/user_storage/{user_hash}?user_hash=<base16_encoded_hash>
```

**Benefits**:
- Only syncs data for specific user_hash
- Reduced bandwidth usage
- Optimized for single-user queries
- Electric optimizes `field = constant` pattern efficiently
- Scales to millions of concurrent shapes

#### 5.1.2 Option 2: Full Table Sync (UserCard Pattern)

**Endpoint**: `GET /electric/v1/user_storage`

**Router Configuration**:
```elixir
sync "/user_storage", Chat.Data.Schemas.UserStorage
```

**Client Request Example**:
```
GET /electric/v1/user_storage
```

**Benefits**:
- Simpler implementation (matches existing UserCard pattern)
- Client-side filtering after sync
- Works well since values are encrypted
- Suitable for public read access model

### 5.2 Write Operations (Ingest Endpoint)

All write operations (create, update, delete) use the centralized ingest endpoint.

**Endpoint**: `POST /electric/v1/ingest`

**Request Format**:
```json
{
  "mutations": [
    {
      "table": "user_storage",
      "operation": "insert",
      "data": {
        "user_hash": "<base16_encoded_hash>",
        "uuid": "<uuid>",
        "value": "<encrypted_blob>"
      }
    }
  ],
  "auth": {
    "challenge_id": "<challenge_id>",
    "signature": "<base64_signature>"
  }
}
```

**Operations**: `insert`, `update`, `delete`

**Batch Operations**: Multiple mutations supported in single request

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

**Required Fields**:
- `mutations[].table`: Must be "user_storage"
- `mutations[].operation`: One of: insert, update, delete
- `mutations[].data.user_hash`: Base16-encoded hash (hex string)
- `mutations[].data.uuid`: Client-generated UUID
- `mutations[].data.value`: Encrypted blob (for insert/update)
- `auth.challenge_id`: Valid challenge identifier
- `auth.signature`: Base64-encoded signature

**Constraints**:
- Value size ≤ 10 MB (before base64 encoding)
- All mutations in batch must target same user_hash
- UUID must be unique for insert operations

## 6. Data Model

**Primary Table**: `user_storage`

**Key Fields**:
- `user_hash`: Binary, part of composite primary key, identifies storage owner
- `uuid`: UUID, part of composite primary key, client-generated
- `value`: Binary, encrypted blob, ≤10 MB

**Indexes**:
- Composite primary key on `(user_hash, uuid)`
- Additional indexes as needed for query optimization

**PostgreSQL Publication**:
- Table must be added to `electric_publication_default`
- Enables Electric replication

For complete schema definition, see [pq_user.md](./pq_user.md).

## 7. Implementation Details

### 7.1 Reference Implementation

The User Storage implementation follows the existing UserCard system pattern:

**Key Reference Files**:
1. **Ingest Endpoint**: [lib/chat_web/controllers/electric_controller.ex](../../lib/chat_web/controllers/electric_controller.ex)
2. **Shape Sync Route**: [lib/chat_web/router.ex:145](../../lib/chat_web/router.ex#L145)
3. **PoP Protocol**: [docs/reqs/electric-proof-of-possesion.md](./electric-proof-of-possesion.md)

### 7.2 PostgreSQL Configuration

**Publication Setup**:
Add `user_storage` table to Electric publication following the pattern from migration:
```
20260219091709_add_user_cards_to_electric_publication.exs
```

### 7.3 Data Encoding

**Binary Field Encoding**:
- `user_hash`: Base16-encoded (hex string) for JSON transport
- `value`: Stored as-is by server; client MAY use base64 encoding to optimize traffic
- Server stores value without modification
- Response shapes return data in same encoding as received

### 7.4 Performance Considerations

**Electric Shape Optimization**:
- Electric optimizes `field = constant` WHERE clause patterns
- Option 1 (filtered shapes) remains efficient with millions of concurrent shapes
- Per-user shape filtering reduces client bandwidth and processing

**Batch Operations**:
- Single database transaction for all mutations in batch
- Single PoP verification for entire batch
- Reduces round-trips for bulk operations

## 8. Client Responsibilities

### 8.1 Encryption
- Client MUST encrypt values before sending to server
- Server stores encrypted blobs without decryption
- Encryption ensures privacy despite public read access

### 8.2 UUID Management
- Client MUST generate UUIDs for new storage entries
- Client MUST track UUID-to-key mapping locally
- Client MUST handle UUID conflicts (409 responses)

### 8.3 Key Listing
- Client implements key listing via shape data filtering
- All user's storage entries available through shape subscription
- Filter by `user_hash` on client side (Option 2) or server side (Option 1)

## 9. References

### 9.1 Electric Documentation
- [Electric Shapes Guide](https://electric-sql.com/docs/guides/shapes) - Core concepts and where clause filtering
- [Electric HTTP API](https://electric-sql.com/openapi) - REST API reference
- [Phoenix.Sync Documentation](https://hexdocs.pm/phoenix_sync/) - Phoenix integration (v0.6.1)
- [Phoenix.Sync.Shape](https://hexdocs.pm/phoenix_sync/Phoenix.Sync.Shape.html) - Shape configuration options
- [Phoenix Integration Guide](https://electric-sql.com/docs/integrations/phoenix) - Electric + Phoenix setup

### 9.2 Related Specifications
- [pq_user.md](./pq_user.md) - User Storage schema definition
- [electric-proof-of-possesion.md](./electric-proof-of-possesion.md) - PoP authentication protocol
- UserCard implementation - Reference pattern for this feature




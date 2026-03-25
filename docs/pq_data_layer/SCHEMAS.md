# Database Schemas

This document describes the current database schema for the Chat application.

## Tables Overview

- **user_cards** - User identity and public key information
- **user_storage** - Current state of user storage items
- **user_storage_versions** - Version history of user storage items

---

## user_cards

Stores user identity cards with cryptographic keys and contact information.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `user_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | Unique user identifier hash |
| `sign_pkey` | `binary` | NOT NULL | Signing public key |
| `contact_pkey` | `binary` | NOT NULL | Contact public key |
| `contact_cert` | `binary` | NOT NULL | Contact certificate |
| `crypt_pkey` | `binary` | NOT NULL | Encryption public key |
| `crypt_cert` | `binary` | NOT NULL | Encryption certificate |
| `name` | `string` | NOT NULL | User display name |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Owner's timestamp for versioning |
| `sign_b64` | `binary` | NOT NULL | Base64-encoded signature |

### Constraints

- **Primary Key**: `user_hash`
- **Unique Constraint**: `user_cards_pkey` on `user_hash`

### Module

`Chat.Data.Schemas.UserCard`

---

## user_storage

Stores the current/latest version of user storage items (key-value pairs).

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `user_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | User identifier hash |
| `uuid` | `Ecto.UUID` | PRIMARY KEY | Unique identifier for storage item |
| `value_b64` | `binary` | NOT NULL | Base64-encoded value (max 10MB) |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `parent_sign_hash` | `Chat.Data.Types.UserStorageSignHash` | FOREIGN KEY | Reference to parent version |
| `owner_timestamp` | `integer` | NOT NULL | Owner's timestamp for versioning |
| `sign_b64` | `binary` | NOT NULL | Base64-encoded signature |
| `sign_hash` | `Chat.Data.Types.UserStorageSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `(user_hash, uuid)`
- **Unique Constraint**: `user_storage_pkey` on `(user_hash, uuid)`
- **Foreign Key**: `parent_sign_hash` references `user_storage_versions.sign_hash`
- **Value Size Limit**: Maximum 10,485,760 bytes (10MB)

### Relationships

- `belongs_to :parent_version` → `user_storage_versions` (via `parent_sign_hash`)

### Module

`Chat.Data.Schemas.UserStorage`

---

## user_storage_versions

Stores the complete version history of user storage items, enabling version tracking and conflict resolution.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `user_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | User identifier hash |
| `uuid` | `Ecto.UUID` | PRIMARY KEY | Unique identifier for storage item |
| `sign_hash` | `Chat.Data.Types.UserStorageSignHash` | PRIMARY KEY | Hash of the signature (version identifier) |
| `value_b64` | `binary` | | Base64-encoded value |
| `deleted_flag` | `boolean` | | Soft delete flag |
| `parent_sign_hash` | `Chat.Data.Types.UserStorageSignHash` | FOREIGN KEY | Reference to parent version |
| `owner_timestamp` | `integer` | | Owner's timestamp for versioning |
| `sign_b64` | `binary` | | Base64-encoded signature |

### Constraints

- **Primary Key**: `(user_hash, uuid, sign_hash)`
- **Foreign Key**: `parent_sign_hash` references `user_storage_versions.sign_hash` (self-referential)

### Relationships

- `belongs_to :parent_version` → `user_storage_versions` (via `parent_sign_hash`)
- `has_many :child_versions` ← `user_storage_versions` (via `sign_hash`)

### Module

`Chat.Data.Schemas.UserStorageVersion`

---

## Custom Types

The schemas use custom Ecto types defined in `Chat.Data.Types`:

- **`Chat.Data.Types.UserHash`** - Custom type for user hash identifiers
- **`Chat.Data.Types.UserStorageSignHash`** - Custom type for storage signature hashes

---

## Version History Model

The storage system implements a version history model:

1. **Current State** (`user_storage`): Contains only the latest version of each storage item
2. **Version History** (`user_storage_versions`): Contains all historical versions
3. **Parent-Child Relationships**: Each version can reference its parent via `parent_sign_hash`, forming a version chain
4. **Version Identification**: Each version is uniquely identified by `(user_hash, uuid, sign_hash)`

This design enables:
- Conflict detection and resolution through version chains
- Complete audit trail of all changes
- Distributed synchronization with causal ordering

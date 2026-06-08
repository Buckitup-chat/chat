# Database Schemas

This document describes the current database schema for the Chat application.

## Tables Overview

- **user_cards** - User identity and public key information
- **user_storage** - Current state of user storage items
- **user_storage_versions** - Version history of user storage items
- **dialog_keys** - Dialog key exchange rows (one per participant per dialog)
- **dialog_messages** - Current tip of each dialog message's version chain
- **dialog_messages_versions** - Archived versions of dialog messages
- **dialog_message_reactions** - Encrypted emoji reactions on dialog messages
- **dialog_message_receipts** - Plaintext delivery and read receipts

---

## user_cards

> **Requirement:** [pq_user.md — User Card](../../reqs/pq_user.md#user-card)

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

> **Requirement:** [pq_user.md — User Storage](../../reqs/pq_user.md#user-storage)

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

> **Requirement:** [pq_user.md — User Storage](../../reqs/pq_user.md#user-storage)

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

## dialog_keys

> **Requirement:** [pq_dialogs.md — §1. dialog_keys](../../reqs/pq_dialogs.md#1-dialog_keys)

Stores dialog key exchange rows. One row per participant per dialog — two rows per dialog in the common case (one per direction). The wrapped `sender_msg_key` lets the peer decrypt all messages authored by this sender.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `dialog_hash` | `Chat.Data.Types.DialogHash` | PRIMARY KEY | Dialog identifier |
| `sender_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | Author of this `sender_msg_key` |
| `peer_hash` | `Chat.Data.Types.UserHash` | NOT NULL | The other participant |
| `peer_kem_wrap_key_b64` | `binary` | NOT NULL | ML-KEM ciphertext to peer's `crypt_pkey` |
| `peer_wrapped_msg_key_b64` | `binary` | NOT NULL | AES-256-GCM wrapped `sender_msg_key` (nonce ‖ ciphertext) |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `deleted_flag` | `boolean` | NOT NULL | Blocking marker; `true` = author has blocked peer |
| `sign_b64` | `binary` | NOT NULL | ML-DSA-87 signature by `sender_hash` |

### Constraints

- **Primary Key**: `(dialog_hash, sender_hash)`

### Module

`Chat.Data.Schemas.DialogKey`

---

## dialog_messages

> **Requirement:** [pq_dialogs.md — §2. dialog_messages](../../reqs/pq_dialogs.md#2-dialog_messages)

Current tip of each dialog message's version chain. Each message is identified by a UUID v7-based `message_id`. Content is a single opaque blob: 12-byte AES-GCM nonce followed by AES-256-GCM ciphertext under `sender_msg_key`.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `message_id` | `Chat.Data.Types.DialogMessageId` | PRIMARY KEY | `dmsg_<UUID7>` |
| `dialog_hash` | `Chat.Data.Types.DialogHash` | NOT NULL | Dialog this message belongs to |
| `sender_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Author |
| `content_b64` | `binary` | NOT NULL | 12-byte nonce ‖ AES-256-GCM ciphertext (max 1 MB) |
| `deleted_flag` | `boolean` | NOT NULL | Signed tombstone marker |
| `refs_map_b64` | `binary` | NOT NULL | Encrypted causal-context map (max 1 MB) |
| `parent_sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | | FK → `dialog_messages_versions.sign_hash`; NULL for first version |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic per `message_id` |
| `sign_b64` | `binary` | NOT NULL | ML-DSA-87 signature by `sender_hash` |
| `sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | NOT NULL | `dms_` + hex(SHA3-512(`sign_b64`)) — tip version identity |

### Constraints

- **Primary Key**: `(message_id)`
- **Blob Size Limit**: Maximum 1,048,576 bytes (1 MB) for `content_b64` and `refs_map_b64`

### Module

`Chat.Data.Schemas.DialogMessage`

---

## dialog_messages_versions

> **Requirement:** [pq_dialogs.md — §2a. dialog_messages_versions](../../reqs/pq_dialogs.md#2a-dialog_messages_versions)

Append-only history for `dialog_messages`. On each edit, the superseded tip row is inserted here verbatim; the new tip's `parent_sign_hash` points at this row's `sign_hash`.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `message_id` | `Chat.Data.Types.DialogMessageId` | PRIMARY KEY | Message identifier |
| `sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | PRIMARY KEY | Version identifier |
| `dialog_hash` | `Chat.Data.Types.DialogHash` | | Dialog this version belongs to |
| `sender_hash` | `Chat.Data.Types.UserHash` | | Author |
| `content_b64` | `binary` | | 12-byte nonce ‖ AES-256-GCM ciphertext |
| `deleted_flag` | `boolean` | | Soft delete flag |
| `refs_map_b64` | `binary` | | Encrypted causal-context map |
| `parent_sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | | Self-referential FK; NULL for root version |
| `owner_timestamp` | `integer` | | Owner's timestamp |
| `sign_b64` | `binary` | | ML-DSA-87 signature by `sender_hash` |

### Constraints

- **Primary Key**: `(message_id, sign_hash)`

### Module

`Chat.Data.Schemas.DialogMessageVersion`

---

## dialog_message_reactions

> **Requirement:** [pq_dialogs.md — §3. dialog_message_reactions](../../reqs/pq_dialogs.md#3-dialog_message_reactions)

Encrypted emoji reactions. Each reaction binds to a specific message version via `message_sign_hash`. The emoji is encrypted under `sender_msg_key`; the `reaction_hash` is a keyed HMAC so observers cannot brute-force the emoji space.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `reaction_hash` | `Chat.Data.Types.DialogMessageReactionHash` | PRIMARY KEY | `dmr_` + hex(HMAC-SHA3-512(key, data)) — keyed MAC |
| `dialog_hash` | `Chat.Data.Types.DialogHash` | NOT NULL | Dialog this reaction belongs to |
| `message_id` | `Chat.Data.Types.DialogMessageId` | NOT NULL | Reacted message |
| `message_sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | NOT NULL | Version of the reacted message |
| `reactor_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who reacted |
| `type_b64` | `binary` | NOT NULL | 12-byte nonce ‖ AES-256-GCM ciphertext of the emoji |
| `deleted_flag` | `boolean` | NOT NULL | Signed un-react marker |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic per `reaction_hash` |
| `sign_b64` | `binary` | NOT NULL | ML-DSA-87 signature by `reactor_hash` |

### Constraints

- **Primary Key**: `(reaction_hash)`

### Module

`Chat.Data.Schemas.DialogMessageReaction`

---

## dialog_message_receipts

> **Requirement:** [pq_dialogs.md — §4. dialog_message_receipts](../../reqs/pq_dialogs.md#4-dialog_message_receipts)

Plaintext delivery and read receipts. Each receipt binds to a specific message version via `message_sign_hash`. Receipts are irreversible — no `deleted_flag`.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `receipt_hash` | `Chat.Data.Types.DialogMessageReceiptHash` | PRIMARY KEY | `dmrc_` + hex(SHA3-512(data)) — plain hash |
| `dialog_hash` | `Chat.Data.Types.DialogHash` | NOT NULL | Dialog this receipt belongs to |
| `message_id` | `Chat.Data.Types.DialogMessageId` | NOT NULL | Receipted message |
| `peer_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who generated the receipt |
| `type` | `string` | NOT NULL | `delivered` or `read` (plaintext) |
| `message_sign_hash` | `Chat.Data.Types.DialogMessageSignHash` | NOT NULL | Version of the receipted message |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic per `receipt_hash` |
| `sign_b64` | `binary` | NOT NULL | ML-DSA-87 signature by `peer_hash` |

### Constraints

- **Primary Key**: `(receipt_hash)`
- **Type Values**: `delivered`, `read`

### Module

`Chat.Data.Schemas.DialogMessageReceipt`

---

## Custom Types

The schemas use custom Ecto types defined in `Chat.Data.Types`:

- **`Chat.Data.Types.UserHash`** - Custom type for user hash identifiers
- **`Chat.Data.Types.UserStorageSignHash`** - Custom type for storage signature hashes
- **`Chat.Data.Types.DialogHash`** - Dialog identifier; prefix + 128-char hex
- **`Chat.Data.Types.DialogMessageId`** - Message identifier; `dmsg_<UUID7>` format
- **`Chat.Data.Types.DialogMessageSignHash`** - Message version signature hash; prefix + 128-char hex
- **`Chat.Data.Types.DialogMessageReactionHash`** - Keyed MAC hash for reactions; prefix + 128-char hex
- **`Chat.Data.Types.DialogMessageReceiptHash`** - Receipt hash; prefix + 128-char hex

---

## Version History Model

The storage and dialog systems implement a version history model:

1. **Current State** (`user_storage` / `dialog_messages`): Contains only the latest version of each item
2. **Version History** (`user_storage_versions` / `dialog_messages_versions`): Contains all historical versions
3. **Parent-Child Relationships**: Each version can reference its parent via `parent_sign_hash`, forming a version chain
4. **Version Identification**: Each version is uniquely identified by its composite PK including `sign_hash`

This design enables:
- Conflict detection and resolution through version chains
- Complete audit trail of all changes
- Distributed synchronization with causal ordering

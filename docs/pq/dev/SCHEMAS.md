# Database Schemas

This document describes the current database schema for the Chat application.
All tables listed here are accessible through the `/electric/v1/shapes` endpoint
(gated by `Chat.Data.Shapes` via `ElectricTableGuard`).

## Tables Overview

**User & Storage**

- **user_cards** - User identity and public key information
- **user_storage** - Current state of user storage items
- **user_storage_versions** - Version history of user storage items

**Dialogs**

- **dialog_keys** - Dialog key exchange rows (one per participant per dialog)
- **dialog_messages** - Current tip of each dialog message's version chain
- **dialog_messages_versions** - Archived versions of dialog messages
- **dialog_message_reactions** - Encrypted emoji reactions on dialog messages
- **dialog_message_receipts** - Plaintext delivery and read receipts

**Files**

- **files** - File manifests (one row per completed upload)
- **file_chunks** - File chunk manifests (metadata only; bytes live in ChunkStore)

**Origins**

- **origins** - Origin entities (businesses, venues) with PQ identity

**Reviews**

- **review** - Public reviews on origins
- **review_public_passwords** - Controls public visibility of reviews
- **review_post_right** - KEM-encrypted envelope for publishing a review
- **review_revoke_right** - KEM-encrypted envelope for revoking a review
- **review_password_candidate** - Server-internal staging for unsigned passwords (not synced)
- **review_post_right_candidate** - Server-internal staging for unsigned post rights (not synced)
- **review_revoke_right_candidate** - Server-internal staging for unsigned revoke rights (not synced)
- **review_list** - Per-user encrypted list of review passwords for contacts

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

## files

> **Requirement:** [pq_files.done.md — §1.1 files](../../reqs/files/pq_files.done.md#11-files-electric-synced)

File manifests. One row per completed file upload.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `file_id` | `Chat.Data.Types.FileId` | PRIMARY KEY | Unique file identifier |
| `uploader_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who uploaded the file |
| `total_size` | `integer` | NOT NULL | Total file size in bytes |
| `chunk_size` | `integer` | NOT NULL | Size of each chunk (default 4,194,304 = 4 MB) |
| `chunk_count` | `integer` | NOT NULL | Number of chunks |
| `chunk_sign_hashes` | `{:array, :binary}` | NOT NULL | Ordered list of chunk signature hashes |
| `owner_timestamp` | `integer` | NOT NULL | Owner's timestamp for versioning |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `sign_b64` | `binary` | NOT NULL | Signature by `uploader_hash` |

### Constraints

- **Primary Key**: `file_id`
- **Unique Constraint**: `files_pkey` on `file_id`

### Module

`Chat.Data.Schemas.File`

---

## file_chunks

> **Requirement:** [pq_files.done.md — §1.2 file_chunks](../../reqs/files/pq_files.done.md#12-file_chunks-electric-synced-manifest-only)

File chunk manifests — metadata only (data_hash, size, signature); the encrypted bytes live on the filesystem in ChunkStore.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `file_id` | `Chat.Data.Types.FileId` | PRIMARY KEY | File this chunk belongs to |
| `chunk_index` | `integer` | PRIMARY KEY | Zero-based chunk index |
| `data_hash` | `Chat.Data.Types.FileChunkDataHash` | NOT NULL | Hash of the encrypted chunk data |
| `size` | `integer` | NOT NULL | Chunk size in bytes |
| `uploader_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who uploaded this chunk |
| `owner_timestamp` | `integer` | NOT NULL | Owner's timestamp for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `uploader_hash` |

### Constraints

- **Primary Key**: `(file_id, chunk_index)`
- **Unique Constraint**: `file_chunks_pkey` on `(file_id, chunk_index)`

### Module

`Chat.Data.Schemas.FileChunk`

---

## origins

> **Requirement:** [reviews.md — Origin](../../proposal/reviews.md#origin)

Origin entities (businesses, venues) with their own PQ identity.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `origin_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | Origin's identity hash |
| `owner_hash` | `Chat.Data.Types.UserHash` | NOT NULL | User who owns this origin |
| `owner_cert` | `binary` | NOT NULL | Owner's certificate |
| `name` | `string` | NOT NULL | Display name |
| `moderation_mode` | `Ecto.Enum` | NOT NULL | `none`, `post`, or `pre` |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `origin_hash` |
| `sign_hash` | `Chat.Data.Types.OriginSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `origin_hash`
- **Unique Constraint**: `origins_pkey` on `origin_hash`
- **Moderation Mode Values**: `none`, `post`, `pre`

### Module

`Chat.Data.Schemas.Origin`

---

## review

> **Requirement:** [reviews.md — Content model](../../proposal/reviews.md#content-model)

Public reviews on origins. Supports versioning via `parent_sign_hash` chain.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Unique review identifier |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin being reviewed |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Review author |
| `content_b64` | `binary` | NOT NULL | Encrypted review content |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `parent_sign_hash` | `Chat.Data.Types.ReviewSignHash` | | FK to previous version; NULL for first |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `author_hash` |
| `sign_hash` | `Chat.Data.Types.ReviewSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `review_hash`
- **Unique Constraint**: `review_pkey` on `review_hash`

### Module

`Chat.Data.Schemas.Review`

---

## review_public_passwords

> **Requirement:** [reviews.md — to_public](../../proposal/reviews.md#to_public)

Controls public visibility of reviews. A password row makes the review decryptable by anyone who obtains it. The revoke (null `password_b64`) version's `owner_timestamp` must exceed the password version's.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this password belongs to |
| `sign_hash` | `Chat.Data.Types.ReviewPasswordSignHash` | PRIMARY KEY | Version identifier |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `password_b64` | `binary` | | Encrypted password (NULL = revoked) |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who issued this password |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `author_hash` |

### Constraints

- **Primary Key**: `(review_hash, sign_hash)`
- **Unique Constraint**: `review_public_passwords_pkey` on `(review_hash, sign_hash)`

### Module

`Chat.Data.Schemas.ReviewPublicPassword`

---

## review_post_right

> **Requirement:** [reviews.md — Contacts / Key delivery](../../proposal/reviews.md#key-delivery)

KEM-encrypted envelope for publishing a review. Grants a contact the ability to post.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this right belongs to |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who granted this right |
| `kem_ciphertext_b64` | `binary` | NOT NULL | ML-KEM ciphertext |
| `wrapped_row_b64` | `binary` | NOT NULL | AES-wrapped right payload |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `author_hash` |
| `sign_hash` | `Chat.Data.Types.ReviewPostRightSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `review_hash`
- **Unique Constraint**: `review_post_right_pkey` on `review_hash`

### Module

`Chat.Data.Schemas.ReviewPostRight`

---

## review_revoke_right

> **Requirement:** [reviews.md — Contacts / Key delivery](../../proposal/reviews.md#key-delivery)

KEM-encrypted envelope for revoking a review. Grants a contact the ability to revoke.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this right belongs to |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who granted this right |
| `kem_ciphertext_b64` | `binary` | NOT NULL | ML-KEM ciphertext |
| `wrapped_row_b64` | `binary` | NOT NULL | AES-wrapped right payload |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `author_hash` |
| `sign_hash` | `Chat.Data.Types.ReviewRevokeRightSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `review_hash`
- **Unique Constraint**: `review_revoke_right_pkey` on `review_hash`

### Module

`Chat.Data.Schemas.ReviewRevokeRight`

---

## review_password_candidate

Server-internal staging for unsigned review passwords. Not synced via Electric — used only during moderated review flows. Mirrors `review_public_passwords` but adds `inserted_at` for candidate lifecycle.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this candidate belongs to |
| `sign_hash` | `Chat.Data.Types.ReviewPasswordSignHash` | PRIMARY KEY | Version identifier |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `password_b64` | `binary` | | Encrypted password |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who issued this password |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `author_hash` |

### Constraints

- **Primary Key**: `(review_hash, sign_hash)`
- **Unique Constraint**: `review_password_candidate_pkey` on `(review_hash, sign_hash)`

### Module

`Chat.Data.Schemas.ReviewPasswordCandidate`

---

## review_post_right_candidate

Server-internal staging for unsigned post rights. Not synced via Electric. Mirrors `review_post_right` but adds `inserted_at` for candidate lifecycle.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this candidate belongs to |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who granted this right |
| `kem_ciphertext_b64` | `binary` | NOT NULL | ML-KEM ciphertext |
| `wrapped_row_b64` | `binary` | NOT NULL | AES-wrapped right payload |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | | Signature (set after signing) |
| `sign_hash` | `Chat.Data.Types.ReviewPostRightSignHash` | | Hash of the signature (set after signing) |
| `inserted_at` | `integer` | NOT NULL | Server insertion timestamp |

### Constraints

- **Primary Key**: `review_hash`
- **Unique Constraint**: `review_post_right_candidate_pkey` on `review_hash`

### Module

`Chat.Data.Schemas.ReviewPostRightCandidate`

---

## review_revoke_right_candidate

Server-internal staging for unsigned revoke rights. Not synced via Electric. Mirrors `review_revoke_right` but adds `inserted_at` for candidate lifecycle.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this candidate belongs to |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `author_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Who granted this right |
| `kem_ciphertext_b64` | `binary` | NOT NULL | ML-KEM ciphertext |
| `wrapped_row_b64` | `binary` | NOT NULL | AES-wrapped right payload |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | | Signature (set after signing) |
| `sign_hash` | `Chat.Data.Types.ReviewRevokeRightSignHash` | | Hash of the signature (set after signing) |
| `inserted_at` | `integer` | NOT NULL | Server insertion timestamp |

### Constraints

- **Primary Key**: `review_hash`
- **Unique Constraint**: `review_revoke_right_candidate_pkey` on `review_hash`

### Module

`Chat.Data.Schemas.ReviewRevokeRightCandidate`

---

## review_list

> **Requirement:** [reviews.md — Contacts / Reading a contact's reviews](../../proposal/reviews.md#reading-a-contacts-reviews)

Per-user encrypted list of review passwords for contacts. Each row links a user to a review, carrying the encrypted password and optional sign-hash references to the password, post-right, and revoke-right versions the user last saw.

### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `user_hash` | `Chat.Data.Types.UserHash` | PRIMARY KEY | User who holds this list entry |
| `review_hash` | `Chat.Data.Types.ReviewHash` | PRIMARY KEY | Review this entry refers to |
| `origin_hash` | `Chat.Data.Types.UserHash` | NOT NULL | Origin the review targets |
| `password_b64` | `binary` | NOT NULL | Encrypted review password |
| `review_password_sign_hash` | `Chat.Data.Types.ReviewPasswordSignHash` | | Last-seen password version |
| `post_right_sign_hash` | `Chat.Data.Types.ReviewPostRightSignHash` | | Last-seen post-right version |
| `revoke_right_sign_hash` | `Chat.Data.Types.ReviewRevokeRightSignHash` | | Last-seen revoke-right version |
| `deleted_flag` | `boolean` | NOT NULL | Soft delete flag |
| `owner_timestamp` | `integer` | NOT NULL | Monotonic counter for versioning |
| `sign_b64` | `binary` | NOT NULL | Signature by `user_hash` |
| `sign_hash` | `Chat.Data.Types.ReviewListSignHash` | NOT NULL | Hash of the signature |

### Constraints

- **Primary Key**: `(user_hash, review_hash)`
- **Unique Constraint**: `review_list_pkey` on `(user_hash, review_hash)`

### Module

`Chat.Data.Schemas.ReviewList`

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
- **`Chat.Data.Types.FileId`** - File identifier
- **`Chat.Data.Types.FileChunkDataHash`** - Hash of encrypted chunk data
- **`Chat.Data.Types.OriginSignHash`** - Origin signature hash; prefix + 128-char hex
- **`Chat.Data.Types.ReviewHash`** - Review identifier
- **`Chat.Data.Types.ReviewSignHash`** - Review signature hash
- **`Chat.Data.Types.ReviewPasswordSignHash`** - Review password signature hash
- **`Chat.Data.Types.ReviewPostRightSignHash`** - Post-right signature hash
- **`Chat.Data.Types.ReviewRevokeRightSignHash`** - Revoke-right signature hash
- **`Chat.Data.Types.ReviewListSignHash`** - Review list entry signature hash

---

## Shape Registry

All shapes are registered in `Chat.Data.Shapes` (`lib/chat/data/shapes.ex`). The `/electric/v1/shapes` endpoint allows client-controlled shapes for any table in this registry, filtered by `ChatWeb.Plugs.ElectricTableGuard`.

**Syncable shapes** (available via Electric sync):

| Shape Name | Schema Module | Versions Schema |
|------------|---------------|-----------------|
| `user_card` | `UserCard` | — |
| `user_storage` | `UserStorage` | `UserStorageVersion` |
| `dialog_keys` | `DialogKey` | — |
| `dialog_messages` | `DialogMessage` | `DialogMessageVersion` |
| `dialog_message_reactions` | `DialogMessageReaction` | — |
| `dialog_message_receipts` | `DialogMessageReceipt` | — |
| `file` | `File` | — |
| `file_chunk` | `FileChunk` | — |
| `origin` | `Origin` | — |
| `review` | `Review` | — |
| `review_public_passwords` | `ReviewPublicPassword` | — |
| `review_post_right` | `ReviewPostRight` | — |
| `review_revoke_right` | `ReviewRevokeRight` | — |
| `review_list` | `ReviewList` | — |

**Not syncable** (server-internal only, in the registry but excluded from Electric sync):

| Shape Name | Schema Module |
|------------|---------------|
| `review_password_candidate` | `ReviewPasswordCandidate` |
| `review_post_right_candidate` | `ReviewPostRightCandidate` |
| `review_revoke_right_candidate` | `ReviewRevokeRightCandidate` |

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

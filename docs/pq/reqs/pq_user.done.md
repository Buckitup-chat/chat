## Purpose

Users are identified by a post-quantum keypair they generate locally. There is no registration — a user proves identity by signing a challenge with their `sign_skey`. The server only stores public keys.

Once registered, users can:
- Store arbitrary encrypted data — see [pq_user_storage.md](./pq_user_storage.md)
- Communicate with other users — see [pq_dialogs.md](./pq_dialogs.md)

Secret keys never leave the Frontend. If the server is compromised, it holds no private keys and no plaintext data.

---

## Algorithms & Fields

### Fields

| Field | Size | Algorithm / Format | Notes |
|---|---|---|---|
| `user_hash` | 130 chars | `"u_" + hex(SHA3-512(sign_pkey))` | URL-friendly hex string with prefix |
| `sign_pkey` | ~2592 bytes | ML-DSA-87 (FIPS 204) | Post-quantum signing public key |
| `sign_skey` | ~4896 bytes | ML-DSA-87 (FIPS 204) | Post-quantum signing private key; FE/bots only |
| `crypt_pkey` | ~1568 bytes | ML-KEM-1024 (FIPS 203) | Post-quantum KEM encapsulation key |
| `crypt_skey` | ~3168 bytes | ML-KEM-1024 (FIPS 203) | Post-quantum KEM decapsulation key; FE/bots only |
| `crypt_cert` | ~4627 bytes | ML-DSA-87 signature of `crypt_pkey` | Binds encryption key to identity |
| `contact_pkey` | 33 bytes | secp256k1 compressed | Classical key exchange (Curvy) |
| `contact_skey` | 32 bytes | secp256k1 | Classical private key; FE/bots only |
| `contact_cert` | ~4627 bytes | ML-DSA-87 signature of `contact_pkey` | Binds contact key to identity |
| `name` | text | UTF-8 | Display name |
| `deleted_flag` | boolean | true/false | Soft delete marker; true indicates deleted |
| `owner_timestamp` | integer | Monotonic counter | Prevents replay attacks; must increase on updates |
| `sign_b64` | ~4627 bytes | ML-DSA-87 signature | Signature of all fields except sign_b64 itself |

### Algorithms

| Purpose | Algorithm | Standard | Implementation |
|---|---|---|---|
| Identity hash | SHA3-512 | NIST FIPS 202 | `EnigmaPq.hash/1` |
| Signing | ML-DSA-87 | NIST FIPS 204 | `EnigmaPq.sign/2`, `EnigmaPq.verify/3` |
| Key encapsulation | ML-KEM-1024 | NIST FIPS 203 | `EnigmaPq.encapsulate_secret/1`, `EnigmaPq.decapsulate_secret/2` |
| Contact key exchange | secp256k1 ECDH | SEC 2 | `Enigma.compute_secret/2` (Curvy) |
| Symmetric encryption | AES-256-GCM | NIST SP 800-38D | `EnigmaPq.aes_gcm_encrypt/2`, `EnigmaPq.aes_gcm_decrypt/2` |
| Key derivation | HKDF-SHA3-256 | RFC 5869 | `EnigmaPq.hkdf_derive/3` |
| HMAC (KDF PRF) | HMAC-SHA3-256 | RFC 2104 | `EnigmaPq.hmac_sha3_256/2` |
| HMAC (reaction MAC) | HMAC-SHA3-512 | RFC 2104 | `EnigmaPq.hmac_sha3_512/2` |
| Secret sharing | Shamir's Secret Sharing | — | `Enigma.hide_secret_in_shares/3` (KeyX) |

All PQ primitives live in [`lib/enigma_pq/enigma_pq.ex`](../../lib/enigma_pq/enigma_pq.ex). Classical primitives remain in [`lib/enigma.ex`](../../lib/enigma.ex).

### Certificate format

Both `crypt_cert` and `contact_cert` are raw ML-DSA-87 signatures:

```
cert = ML-DSA-87.sign(public_key_bytes, sign_skey)
```

Verification: `ML-DSA-87.verify(public_key_bytes, cert, sign_pkey)`

No X.509 or ASN.1 wrapping — bare binary signatures bound by identity via `user_hash`.

---

## User

### User creation

All keys are generated locally on the Frontend. There is no server-side registration step — the user submits their User Card and is immediately recognized by `user_hash` on future visits.

Authentication is implicit: the server trusts whoever can produce a valid ML-DSA-87 signature with `sign_skey` matching a known `sign_pkey`.

Key generation:

- sign keypair — ML-DSA-87 (FIPS 204)
- crypt keypair — ML-KEM-1024 (FIPS 203)
- contact keypair — secp256k1

Derived values:

- `user_hash` = `"u_" + Base.encode16(SHA3-512(sign_pkey), case: :lower)`
- `crypt_cert` = `ML-DSA-87.sign(crypt_pkey, sign_skey)`
- `contact_cert` = `ML-DSA-87.sign(contact_pkey, sign_skey)`

Secret keys (`sign_skey`, `crypt_skey`, `contact_skey`) are stored in the User Identity on the Frontend only and never sent to the server.

See [`EnigmaPq.generate_identity/0`](../../lib/enigma_pq/enigma_pq.ex#L31) for the server-side equivalent used in bots and tests.

### User Card

User card is stored in the database.

- user_hash
- sign_pkey
- crypt_pkey
- crypt_cert
- contact_pkey
- contact_cert
- name
- deleted_flag
- owner_timestamp
- sign_b64

Schema: [`Chat.Data.Schemas.UserCard`](../../lib/chat/data/schemas/user_card.ex)

Changesets: `create_changeset`, `update_name_changeset`, `update_deleted_flag_changeset`.

Protocol implementations:
- `Chat.Data.User.Validation.TimestampedData` — exposes `owner_timestamp` for replay protection
- `Chat.Data.Integrity.Signable` — defines signable fields, signing key, and signature extraction for integrity verification
- `Enigma.Hash.Protocol` — makes the card hashable via `user_hash`

### User Identity [FE only, bots, or tests]

User identity is a frontend-only concept. No Elixir struct exists on the server side.

- user_card (embedded or linked)
- sign_skey
- crypt_skey
- contact_skey
- is_trusted_origin

### User Storage

User storage is a versioned key-value store with integrity protection.
`user_hash` scopes entries to a specific user.
`uuid` identifies individual storage items on the Frontend.
`value_b64` holds the payload — encryption is the Frontend's responsibility.

Fields:

- user_hash
- uuid
- value_b64
- deleted_flag
- parent_sign_hash — links to the previous version (nullable for first version)
- owner_timestamp — monotonic counter; must increase on updates
- sign_b64 — ML-DSA-87 signature over all fields except `sign_b64` and `sign_hash`
- sign_hash — `"uss_"` prefixed SHA3-512 hash of the signature; uniquely identifies this version

Schema: [`Chat.Data.Schemas.UserStorage`](../../lib/chat/data/schemas/user_storage.ex)

Changesets: `create_changeset`, `update_changeset`.

Associations:
- `belongs_to :parent_version` → `user_storage_versions` (via `parent_sign_hash`)

Protocol implementations:
- `Chat.Data.User.Validation.TimestampedData` — exposes `owner_timestamp` for replay protection
- `Chat.Data.Integrity.Signable` — defines signable fields; signing key is resolved from the user's card

### User Storage Versions

Archived versions of user storage entries, enabling version history and conflict resolution.
When a newer version arrives, the existing entry is archived here before being overwritten.

Fields mirror User Storage: `user_hash`, `uuid`, `sign_hash`, `value_b64`, `deleted_flag`, `parent_sign_hash`, `owner_timestamp`, `sign_b64`.

Primary key: `(user_hash, uuid, sign_hash)` — a triple key since multiple versions can exist per storage item.

Self-referential: `parent_sign_hash` references `sign_hash` within the same table, forming a version chain.

Schema: [`Chat.Data.Schemas.UserStorageVersion`](../../lib/chat/data/schemas/user_storage_version.ex)

---

## Data Integrity

### Signature verification

All user-facing data (cards and storage) carries a `sign_b64` field — an ML-DSA-87 signature over a deterministic payload of the record's other fields. The `Chat.Data.Integrity` module and `Signable` protocol define how each schema produces its signature payload.

Payload construction (field-order-independent):
1. Collect signable fields (all fields except `sign_b64`, `sign_hash`, metadata)
2. Sort by field name alphabetically
3. Encode each field by suffix convention (`_b64`/`_cert`/`_pkey` → Base64, `_hash` → prefixed hex, booleans/integers → string)
4. Concatenate

Module: [`Chat.Data.Integrity`](../../lib/chat/data/integrity.ex)

### Timestamp validation

Updates must carry an `owner_timestamp` strictly greater than the existing record's. The `TimestampedData` protocol extracts the current timestamp from any schema that implements it. Validation rejects stale or replayed updates.

### Electric sync validation

User data arrives via Electric SQL replication. The `Chat.Data.User.Validation` module gates all sync operations:

- **Authorization**: `user_card_allowed/2` and `user_storage_allowed/2` verify a challenge-response signature against the user's `sign_pkey`
- **Card validation**: `user_card_validate/3` runs the appropriate changeset, verifies the signature, and checks timestamp ordering
- **Storage validation**: `user_storage_validate/3` and `user_storage_validate_with_versioning/3` handle insert/update with automatic version archival
- **Pre-apply versioning**: `user_storage_pre_apply_versioning/3` archives existing entries to the versions table when a newer version arrives

Module: [`Chat.Data.User.Validation`](../../lib/chat/data/user/validation.ex)

---

## Implementation

### Custom types

**UserHash**: `"u_"` prefixed, 128-char lowercase hex (64-byte SHA3-512 digest). Uses the `PrefixedHash` macro for cast/dump/load/conversion.

- Type: [`Chat.Data.Types.UserHash`](../../lib/chat/data/types/user_hash.ex)
- Macro: [`Chat.Data.Types.PrefixedHash`](../../lib/chat/data/types/prefixed_hash.ex)
- Prefix constant: [`Chat.Data.Types.Consts.user_prefix/0`](../../lib/chat/data/types/consts.ex#L10) → `"u_"`

**UserStorageSignHash**: `"uss_"` prefixed, same structure. Identifies storage entry versions.

- Type: [`Chat.Data.Types.UserStorageSignHash`](../../lib/chat/data/types/user_storage_sign_hash.ex)
- Prefix constant: [`Chat.Data.Types.Consts.user_storage_sign_prefix/0`](../../lib/chat/data/types/consts.ex#L11) → `"uss_"`

### Database constraints

PostgreSQL validates hash formats via inline CHECK constraints on each table (no domain types):

```SQL
ALTER TABLE user_cards ADD CONSTRAINT user_hash_format_check
  CHECK (user_hash ~ '^u_[a-f0-9]{128}$');
```

Migration: [`20260324074642_convert_hashes_to_text.exs`](../../priv/repo/migrations/20260324074642_convert_hashes_to_text.exs)

**Hash Algorithm: SHA3-512**

- Output: 512 bits (64 bytes) encoded as hex with `"u_"` prefix
- Final format: `"u_" <> Base.encode16(sha3_512_digest, case: :lower)` (130 characters total)
- NIST-approved, post-quantum resistant

### Shortcode Display

For user-friendly display, `user_hash` is shortened to a prefixed 6-character hex code.

- Preserves the prefix and takes the first 6 hex characters after it
- Example: `"u_aabbccdddddddd..."` → `"u_aabbcc"`
- 24 bits = 16.7M combinations for collision-resistant display

Protocol: [`Chat.Proto.Shortcode`](../../lib/chat/proto/shortcode.ex)

Implementations:
- `UserCard` — delegates to the `BitString` implementation via `user_hash`
- `BitString` — splits on `_`, keeps prefix, takes first 6 hex chars
- `Atom` — handles `nil` → `""`

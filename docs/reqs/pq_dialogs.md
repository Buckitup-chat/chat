# Post-Quantum Dialog

A dialog is a two-party conversation between users identified by `user_hash` (see `pq_user.md`). Each side independently authors messages encrypted under a per-author message key. The key is derived deterministically from the author's private material plus the peer's identity, so any of the author's devices can re-derive it without a device registry and without re-running a handshake.

## Goals

- **Symmetric read access** — the author and the peer can both read every message.
- **Either side can initiate** — both sides may independently create their half of the dialog on different devices; state converges to the same `dialog_hash`.
- **Multi-device by derivation, not tracking** — any device holding the author's secret keys re-derives the same `sender_msg_key`. No `user_devices` table, no re-wrap gossip.

## Accepted trade-off

Deterministic derivation means **no forward secrecy at the dialog level**. If any of an author's long-term private keys (`sign_skey`, `kem_skey`, `contact_skey`) leak, every dialog that user authored becomes decryptable retroactively. Rotating these keys means rotating identity.

---

## Schema at a glance

All four dialog tables are self-authenticating via the integrity triad (`sign_b64`, `owner_timestamp`, `deleted_flag`) defined in [02_integrity.md](../electric/pq_data_layer/02_integrity.md). `user_cards` is shown because every verification path starts there — fetch the author's `sign_pkey` / `crypt_pkey` from `user_cards`, then check the dialog row's signature. No database-level foreign keys to `user_cards` exist (PQ rows are self-verifying), but the logical dependency is real.

```mermaid
erDiagram
    user_cards ||--o{ dialog_keys              : "sender_hash,peer_hash"
    user_cards ||--o{ dialog_messages          : "sender_hash"
    user_cards ||--o{ dialog_messages_versions : "sender_hash"
    user_cards ||--o{ dialog_reactions         : "sender_hash"

    dialog_keys ||--o{ dialog_messages          : "dialog_hash"
    dialog_keys ||--o{ dialog_messages_versions : "dialog_hash"
    dialog_keys ||--o{ dialog_reactions         : "dialog_hash"

    dialog_messages          ||--o{ dialog_messages_versions : "message_id"
    dialog_messages_versions ||--o| dialog_messages          : "sign_hash → parent_sign_hash"
    dialog_messages_versions ||--o{ dialog_messages_versions : "sign_hash → parent_sign_hash (self)"

    dialog_messages          ||--o{ dialog_reactions : "message_id"
    dialog_messages_versions ||--o{ dialog_reactions : "sign_hash → message_sign_hash"

    user_cards {
        user_hash_type  user_hash        PK
    }

    dialog_keys {
        dialog_hash_type dialog_hash              PK
        user_hash_type   sender_hash              PK
        user_hash_type   peer_hash
        bytea            peer_kem_wrap_key_b64
        bytea            peer_wrapped_msg_key_b64
        integer          owner_timestamp
        boolean          deleted_flag
        bytea            sign_b64
    }

    dialog_messages {
        dialog_message_id_type        message_id        PK
        dialog_hash_type              dialog_hash       FK
        user_hash_type                sender_hash
        bytea                         content_b64
        boolean                       deleted_flag
        dialog_message_sign_hash_type parent_sign_hash  FK
        integer                       owner_timestamp
        bytea                         sign_b64
        dialog_message_sign_hash_type sign_hash
    }

    dialog_messages_versions {
        dialog_message_id_type        message_id        PK
        dialog_message_sign_hash_type sign_hash         PK
        dialog_hash_type              dialog_hash       FK
        user_hash_type                sender_hash
        bytea                         content_b64
        boolean                       deleted_flag
        dialog_message_sign_hash_type parent_sign_hash  FK
        integer                       owner_timestamp
        bytea                         sign_b64
    }

    dialog_reactions {
        dialog_reaction_hash_type     reaction_hash      PK
        dialog_hash_type              dialog_hash        FK
        dialog_message_id_type        message_id         UK
        user_hash_type                sender_hash        UK
        text                          type               UK
        dialog_message_sign_hash_type message_sign_hash
        boolean                       deleted_flag
        integer                       owner_timestamp
        bytea                         sign_b64
    }
```

Key relationships in words:

- `dialog_keys` has a composite PK `(dialog_hash, sender_hash)`. In the steady state there are two rows per `dialog_hash` — one per direction.
- `dialog_messages.parent_sign_hash` → `dialog_messages_versions.sign_hash` (nullable; NULL for the first version of a message).
- `dialog_messages_versions.parent_sign_hash` → `dialog_messages_versions.sign_hash` (self-referential; append-only chain).
- `dialog_reactions.message_sign_hash` **logically** targets a specific version in `dialog_messages` *or* `dialog_messages_versions` — there is no database FK, because the referenced row can live in either table, and reactions may arrive before the message.

---

## Identifiers

### `dialog_hash`

```
sorted       = sort([user_a_hash, user_b_hash])     # lexicographic on user_hash strings
dialog_hash  = "di_" + hex(SHA3-512(sorted[0] || sorted[1]))
```

- `user_a_hash` = `min(sender_hash, peer_hash)`
- `user_b_hash` = `max(sender_hash, peer_hash)`

Same on both sides ⇒ independent initiation converges.

PostgreSQL domain:

```sql
CREATE DOMAIN dialog_hash_type AS TEXT
  CHECK (VALUE ~ '^di_[a-f0-9]{128}$');
```

---

## Key derivation

Each author derives one `sender_msg_key` per peer. It is the symmetric key for every message that author writes in that dialog.

```
sender_msg_key = SHA3-512(
    "buckitup/dialog-mk/v1"
 || sign_skey
 || kem_skey
 || contact_skey
 || peer_user_hash
)
```

Rationale:

- **Hybrid posture** (per `HYBRID.md`): `kem_skey` is ML-KEM-1024, `contact_skey` is secp256k1. A break in either family alone does not compromise the secret.
- **`sign_skey` is folded in** to bind derivation to the full identity. `sign_skey` never leaves the frontend, same as the other skeys.
- **Domain separation tag** `"buckitup/dialog-mk/v1"` prevents collisions with future derivations (rooms, groups, subchannels).
- **Peer binding by `peer_user_hash`** — itself `SHA3-512(peer_sign_pkey)`, so transitively bound to peer's signing identity.

Symmetric encryption uses AES-256-GCM with `sender_msg_key`; per-message nonce is fresh random 12 bytes prepended to the ciphertext in the single `content_b64` blob.

---

## Key wrapping

Both the author and the peer need to read messages. `sender_msg_key` is wrapped for the peer and published in `dialog_keys`:

- **Peer-wrap** — KEM-encapsulated to the peer's `crypt_pkey`. Lets the peer read.
- **Author reads own messages** by re-deriving `sender_msg_key` deterministically from private keys (no self-wrap column needed).

```
SENDER (wrap, once per dialog)
─────────────────────────────────────────────────────────────
  inputs:  sender_msg_key        (derived, see §Key derivation)
           peer.crypt_pkey       (from peer's user_cards row)

  ┌─────────────────────────────────────────────────────────┐
  │  step 1                                                 │
  │     ML-KEM-1024.Encap(peer.crypt_pkey)                  │
  │            │                                            │
  │            └──►  ( peer_kem_wrap_key , wrap_key )       │
  │                    KEM ciphertext     ephemeral AES key │
  └────────────────────┬──────────────────────────┬─────────┘
                       │                          │
                       │           ┌──────────────┘
                       │           │
                       │           ▼
                       │   ┌─────────────────────────────────┐
                       │   │  step 2                         │
                       │   │     AES-256-GCM.encrypt(        │
                       │   │        key       = wrap_key,    │
                       │   │        plaintext = sender_msg_key) │
                       │   │            │                    │
                       │   │            └──► peer_wrapped_msg_key │
                       │   └────────────────────┬────────────┘
                       │                        │
                       ▼                        ▼
                 ┌────────────────────────────────────────┐
                 │  publish: one row in `dialog_keys`     │
                 │     peer_kem_wrap_key_b64              │
                 │     peer_wrapped_msg_key_b64           │
                 │     (+ identity & signature fields)    │
                 └────────────────────────────────────────┘


PEER (unwrap, on first read)
─────────────────────────────────────────────────────────────
  inputs:  peer_kem_wrap_key      (from dialog_keys)
           peer_wrapped_msg_key   (from dialog_keys)
           own.crypt_skey         (peer's private KEM key, never leaves device)

  ┌─────────────────────────────────────────────────────────┐
  │  step 1                                                 │
  │     ML-KEM-1024.Decap(own.crypt_skey, peer_kem_wrap_key)│
  │            │                                            │
  │            └──►  wrap_key       (same AES key sender used) │
  └────────────────────┬────────────────────────────────────┘
                       │
                       ▼
  ┌─────────────────────────────────────────────────────────┐
  │  step 2                                                 │
  │     AES-256-GCM.decrypt(                                │
  │        key        = wrap_key,                           │
  │        ciphertext = peer_wrapped_msg_key)               │
  │            │                                            │
  │            └──►  sender_msg_key                         │
  │                  (now usable for every message authored │
  │                   by sender in this dialog)             │
  └─────────────────────────────────────────────────────────┘
```

Compact form:

```
wrap:    (peer_kem_wrap_key, wrap_key) = ML-KEM-1024.Encap(peer.crypt_pkey)
         peer_wrapped_msg_key          = AES-256-GCM.encrypt(wrap_key, sender_msg_key)
         publish (peer_kem_wrap_key_b64, peer_wrapped_msg_key_b64)

unwrap:  wrap_key       = ML-KEM-1024.Decap(own.crypt_skey, peer_kem_wrap_key)
         sender_msg_key = AES-256-GCM.decrypt(wrap_key, peer_wrapped_msg_key)
```

Note that `sender_msg_key` is **never** an input to Encap — Encap operates only on the peer's KEM public key. The KEM produces an ephemeral `wrap_key`; that ephemeral key is what actually encrypts `sender_msg_key`.

---

## Tables

There is no `dialogs` table. Participation is derived from `dialog_keys` via `sender_hash = me OR peer_hash = me`, which is also the sync filter. Dialog existence is advisory; trust is in the signed rows below.

### 1. `dialog_keys`

Wrapped `sender_msg_key` published by one author for one dialog. Two rows per dialog in the common case (one per direction). An author republishes the same row idempotently from any of their devices (deterministic `sender_msg_key` ⇒ same plaintext, different KEM randomness ⇒ compatible).

| Column                     | Type               | Notes                                                                                           |
| -------------------------- | ------------------ | ----------------------------------------------------------------------------------------------- |
| `dialog_hash`              | `dialog_hash_type` | PK part                                                                                         |
| `sender_hash`              | `user_hash_type`   | PK part; author of this `sender_msg_key`                                                        |
| `peer_hash`                | `user_hash_type`   | the other participant; enables sync filter and inbox listing without a separate `dialogs` table |
| `peer_kem_wrap_key_b64`    | `bytea`            | ML-KEM ciphertext to peer's `crypt_pkey`                                                        |
| `peer_wrapped_msg_key_b64` | `bytea`            | AES-GCM(sender_msg_key) with ss from `peer_kem_wrap_key_b64`                                    |
| `owner_timestamp`          | `integer`          | Monotonic counter; must increase on updates; prevents replay attacks                            |
| `deleted_flag`             | `boolean`          | Soft delete marker; `true` indicates deleted                                                    |
| `sign_b64`                 | `bytea`            | ML-DSA-87 signature by `sender_hash` over canonical serialization of all preceding columns      |

PK: `(dialog_hash, sender_hash)`.

Self-authenticating per [02_integrity.md](../electric/pq_data_layer/02_integrity.md), same bootstrap as `user_cards`: fetch `user_cards` for `sender_hash`, verify its self-signature, then verify this row's `sign_b64` under that `sign_pkey`. A row with invalid `sign_b64` is rejected on ingest and re-verified on peer-sync receive. Because `dialog_hash`, `peer_hash`, and both KEM ciphertexts are all covered by the signature, no field can be rewritten, retargeted to a different peer, or lifted into a different dialog without detection.

Flooding: an attacker can still publish a row naming an uninvolved `peer_hash` (PoP proves submitter identity, not peer consent). Clients mitigate by hiding a dialog until the local user has either authored a message in it or the peer has published their own `dialog_keys` row for the same `dialog_hash`.

### 2. `dialog_messages`

Current tip of each message's version chain. Each message is identified by `message_id = "dmsg_" + UUID v7` — globally unique and time-ordered within a dialog. Messages follow the integrity triad in [02_integrity.md](../electric/pq_data_layer/02_integrity.md) (`sign_b64`, `owner_timestamp`, `deleted_flag`) and the hash-linked versioning model in [03_data_versioning.md](../electric/pq_data_layer/03_data_versioning.md), mirroring `user_storage` / `user_storage_versions` (see `Chat.Data.Schemas.UserStorage`).

Content is a single opaque blob: the first 12 bytes are the per-message AES-GCM nonce, the remainder is AES-256-GCM ciphertext under `sender_msg_key`. Plaintext shape — bare-string text vs. `{"<type>": <value>}` envelopes for media, plus inline-vs-out-of-band rules — lives in [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md). Keeping the type *inside* the ciphertext means the database never reveals whether a message is text, image, or attachment.

Two cross-author relational fields are deliberately **not** listed in the column table below and will be added by separate specs:

- `prev_message_uuid` — timeline predecessor forming a hash-linked chain per dialog. Owned by [04_ordering.md](../electric/pq_data_layer/04_ordering.md); required because Electric sync offers no delivery-order guarantee and `parent_sign_hash` only chains revisions *by the same author*.
- `reply_to_message_id` — explicit reply/quote target (any earlier `message_id` in the same dialog, not necessarily the tip). Owned by [05_branching.md](../electric/pq_data_layer/05_branching.md); the `{"quote": ...}` envelope from [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md) carries display payload, while `reply_to_message_id` carries the structural link so it is covered by `sign_b64` and tamper-evident.

Both will be signable columns (covered by `sign_b64`) rather than in-envelope fields, so that ingest can reject forged or cross-dialog links without decrypting.

| Column             | Type                            | Notes                                                                                                       |
| ------------------ | ------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `message_id`       | `dialog_message_id_type`        | PK; `dmsg_<UUID7>`                                                                                          |
| `dialog_hash`      | `dialog_hash_type`              | dialog this message belongs to                                                                              |
| `sender_hash`      | `user_hash_type`                | author                                                                                                      |
| `content_b64`          | `bytea`                         | 12-byte AES-GCM nonce ‖ AES-256-GCM ciphertext of the JSON payload — see [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md). Empty when `deleted_flag = true` |
| `deleted_flag`     | `boolean`                       | Signed tombstone marker; retractions are a new tip with empty `content_b64` and `deleted_flag: true`        |
| `parent_sign_hash` | `dialog_message_sign_hash_type` | FK → `dialog_messages_versions.sign_hash`; NULL for the first version                                       |
| `owner_timestamp`  | `integer`                       | Monotonic per `message_id`; strictly increases on edit; prevents replay                                     |
| `sign_b64`         | `bytea`                         | ML-DSA-87 signature by `sender_hash` over the signable fields (everything except `sign_b64` / `sign_hash`)  |
| `sign_hash`        | `dialog_message_sign_hash_type` | `dms_` + hex(SHA3-512(`sign_b64`)) — identity of this tip version. Denormalized convenience copy per [03_data_versioning.md](../electric/pq_data_layer/03_data_versioning.md): derivable from `sign_b64`, not itself covered by the signature, nothing FK-references it; kept on the master to avoid recomputing the hash when archiving the outgoing tip and when populating the next edit's `parent_sign_hash`. |

PK: `(message_id)`. UNIQUE: `(dialog_hash, message_id)` — supports dialog-scoped sync filtering and inbox listings without a separate `dialogs` table.

Postgres domains:

```sql
CREATE DOMAIN dialog_message_id_type AS TEXT
  CHECK (VALUE ~ '^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

CREATE DOMAIN dialog_message_sign_hash_type AS TEXT
  CHECK (VALUE ~ '^dms_[a-f0-9]{128}$');
```

Self-authenticating per [02_integrity.md](../electric/pq_data_layer/02_integrity.md): verify `sign_b64` under `sender_hash`'s `sign_pkey` (from `user_cards`). An incoming update with `owner_timestamp <= existing` is rejected as a replay even if the signature verifies. Deletes are a new signed tip with `deleted_flag: true` and a higher `owner_timestamp` — there is no unsigned server-side delete.

### 2a. `dialog_messages_versions`

Append-only history for `dialog_messages`, mirroring `Chat.Data.Schemas.UserStorageVersion`. On each edit, the superseded tip row is inserted here verbatim (carrying its own `sign_hash`); the new tip's `parent_sign_hash` then points at that row's `sign_hash`. Because `sign_b64` covers `parent_sign_hash`, rewriting any historical version breaks every descendant's signature.

| Column             | Type                            | Notes                                                                                       |
| ------------------ | ------------------------------- | ------------------------------------------------------------------------------------------- |
| `message_id`       | `dialog_message_id_type`        | PK part                                                                                     |
| `sign_hash`        | `dialog_message_sign_hash_type` | PK part; `dms_` + hex(SHA3-512(`sign_b64`)) — identity of this version                      |
| `dialog_hash`      | `dialog_hash_type`              |                                                                                             |
| `sender_hash`      | `user_hash_type`                |                                                                                             |
| `content_b64`          | `bytea`                         | 12-byte AES-GCM nonce ‖ ciphertext (same shape as the tip)                                  |
| `deleted_flag`     | `boolean`                       |                                                                                             |
| `parent_sign_hash` | `dialog_message_sign_hash_type` | Self-referential FK into `dialog_messages_versions.sign_hash`; NULL for the root version    |
| `owner_timestamp`  | `integer`                       |                                                                                             |
| `sign_b64`         | `bytea`                         | ML-DSA-87 signature by `sender_hash` covering every field except `sign_b64` and `sign_hash` |

PK: `(message_id, sign_hash)`. Append-only — rows are never mutated. A version cannot be inserted unless its `parent_sign_hash` is already known locally (or NULL for the root).

### 3. `dialog_reactions`

Reactions bind to a specific message **version** via `message_sign_hash` — the `sign_hash` (SHA3-512 of `sign_b64`) of the reacted-to version in the message's chain (tip or historical). Reacting to an edited message does not automatically carry over.

| Column              | Type                            | Notes                                                                                               |
| ------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------- |
| `reaction_hash`     | `dialog_reaction_hash_type`     | PK; `dr_` + hex(SHA3-512(`dialog_hash` ‖ `message_id` ‖ `sender_hash` ‖ `type`))                    |
| `dialog_hash`       | `dialog_hash_type`              | unique-key part                                                                                     |
| `message_id`        | `dialog_message_id_type`        | unique-key part; `dmsg_<UUID7>`                                                                     |
| `sender_hash`       | `user_hash_type`                | unique-key part; who reacted                                                                        |
| `type`              | `text`                          | unique-key part; reaction kind                                                                      |
| `message_sign_hash` | `dialog_message_sign_hash_type` | `sign_hash` of the reacted version in `dialog_messages(_versions)`                                  |
| `deleted_flag`      | `boolean`                       | Signed un-react marker; toggling a reaction is a new row with `true` and a higher `owner_timestamp` |
| `owner_timestamp`   | `integer`                       | Monotonic per `reaction_hash`; prevents replay                                                      |
| `sign_b64`          | `bytea`                         | ML-DSA-87 signature by `sender_hash` over all preceding columns                                     |

PK: `(reaction_hash)`. UNIQUE: `(dialog_hash, message_id, sender_hash, type)` — enforces one reaction per `(message, reactor, type)` and lets clients derive `reaction_hash` deterministically without a lookup.

Postgres domain:

```sql
CREATE DOMAIN dialog_reaction_hash_type AS TEXT
  CHECK (VALUE ~ '^dr_[a-f0-9]{128}$');
```

Carries the full integrity triad per [02_integrity.md](../electric/pq_data_layer/02_integrity.md): `sign_b64` over all other fields, `owner_timestamp` strictly monotonic per `reaction_hash`, `deleted_flag` as a signed un-react. Reactions are not versioned (no chain) — the row is overwritten on each new signed update. Because `reaction_hash` is derived from the unique-key fields, an attacker cannot reuse a `reaction_hash` to point at a different `(message, reactor, type)` — the hash would no longer match.

**Reserved `type` values for receipts:**

- `delivered` — published by the peer's device when the message lands locally. Bound to the version actually received via `message_sign_hash`.
- `read` — published by the peer when their UI displays the message.

Receipts use the same row shape and integrity contract as emoji reactions; the only difference is the well-known `type` string and the convention that they are not user-toggled (`deleted_flag` stays `false` in normal use). This avoids a separate receipts table.

---

## Flows

### Author sends a message

1. Compute `dialog_hash` from `(sender_hash, peer_hash)`.
2. Derive `sender_msg_key` (formula above).
3. If no `dialog_keys` row exists for `(dialog_hash, sender_hash)`: wrap `sender_msg_key` self + peer, sign, insert (row carries `peer_hash`).
4. Build message: fresh `message_id = "dmsg_" + UUID v7`, `parent_sign_hash = NULL`, `deleted_flag = false`, fresh `owner_timestamp`. Encode payload as JSON (bare string for text, `{"<type>": <value>}` for compound), AES-GCM encrypt under `sender_msg_key` with a fresh 12-byte nonce, store as `content_b64 = nonce ‖ ciphertext`. Sign, set `sign_hash = "dms_" + hex(SHA3-512(sign_b64))`, insert into `dialog_messages`. Edits append the prior tip to `dialog_messages_versions` and rewrite the tip with `parent_sign_hash` set to the superseded row's `sign_hash` and a higher `owner_timestamp`.

### Peer reads

1. Fetch `dialog_keys` rows for `dialog_hash`.
2. For each row authored by a counterparty: verify `sign_b64` against `sender_hash`'s `sign_pkey`, then unwrap via `peer_kem_wrap_key_b64` / `peer_wrapped_msg_key_b64` using own `crypt_skey` ⇒ their `sender_msg_key`.
3. For messages authored by self: re-derive `sender_msg_key` from own private keys (deterministic derivation). (Or unwrap from a counterparty's `dialog_keys` row where self is the peer.)
4. For each `dialog_messages` row: verify `sign_b64`, split `content_b64` into the 12-byte nonce and ciphertext, AES-GCM decrypt under the matching author's `sender_msg_key`, then JSON-decode the plaintext to discover the content shape.

### Author on a new device

1. Device has the author's `sign_skey`, `kem_skey`, `contact_skey` (from User Identity, per `pq_user.md`).
2. Re-derive `sender_msg_key` — same value as on any other device.
3. Can read own past messages by re-deriving `sender_msg_key` from private keys (deterministic derivation).
4. To write: no new `dialog_keys` row needed (one already exists for `(dialog_hash, sender_hash)`); proceed to insert `dialog_messages`.

### Either side initiates independently

Both sides compute the same `dialog_hash`. Each inserts its own `dialog_keys` row keyed on its own `sender_hash`, naming the other as `peer_hash`. No coordination needed. A client listing inbox dialogs queries `dialog_keys WHERE sender_hash = me OR peer_hash = me`.

---

## Out of scope

- **Group conversations** — covered by `pq_rooms.md` (TBD); this doc covers two-party dialogs only.
- **Cross-author message ordering** — the `dialog_messages` schema here gives per-author revision chains (`parent_sign_hash`) but no shared timeline across authors. The hash-linked `prev_message_uuid` chain that provides a tamper-evident total order per dialog is owned by [04_ordering.md](../electric/pq_data_layer/04_ordering.md); until it lands, clients linearize by UUIDv7 timestamp as a best-effort display order.
- **Replies and concurrent forks** — explicit reply targeting and sibling-branch rendering (two peers answering the same tip) are owned by [05_branching.md](../electric/pq_data_layer/05_branching.md), which adds `reply_to_message_id` on top of the ordering chain. The `{"quote": ...}` envelope in [07_content_polymorphism.md](../electric/pq_data_layer/07_content_polymorphism.md) is a UI-payload concern and does not replace the structural pointer.
- **Sync filtering** — which rows propagate to which peer is a frontend / sync-layer choice, not part of the dialog data contract.

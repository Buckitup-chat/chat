# Post-Quantum Dialog

A dialog is a two-party conversation between users identified by `user_hash` (see `pq_user.md`). Each side independently authors messages encrypted under a per-author message key. The key is derived deterministically from the author's private material plus the peer's identity, so any of the author's devices can re-derive it without a device registry and without re-running a handshake.

## Goals

- **Symmetric read access** — the author and the peer can both read every message.
- **Either side can initiate** — both sides may independently create their half of the dialog on different devices; state converges to the same `dialog_hash`.
- **Multi-device by derivation, not tracking** — any device holding the author's secret keys re-derives the same `sender_msg_key`. No `user_devices` table, no re-wrap gossip.

## Accepted trade-off

Deterministic derivation means **no forward secrecy at the dialog level**. If any of an author's long-term private keys (`sign_skey`, `kem_skey`, `contact_skey`) leak, every dialog that user authored becomes decryptable retroactively. Rotating these keys means rotating identity.

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

Symmetric encryption uses AES-256-GCM with `sender_msg_key`; per-message nonce is fresh random 12 bytes stored beside the ciphertext.

---

## Key wrapping

Both the author and the peer need to read messages. `sender_msg_key` is wrapped for the peer and published in `dialog_keys`:

- **Peer-wrap** — KEM-encapsulated to the peer's `crypt_pkey`. Lets the peer read.
- **Author reads own messages** by re-deriving `sender_msg_key` deterministically from private keys (no self-wrap column needed).

```
                        sender_msg_key
                            │
                    ML-KEM-1024.Encap(
                     peer's crypt_pkey)
                            │
                     (peer_kem_wrap_key_b64,
                      ss_peer)
                            │
                    AES-256-GCM.enc(
                     key=ss_peer,
                     plaintext=sender_msg_key)
                            │
                  peer_wrapped_msg_key_b64
                            │
                     ► dialog_keys ◄
                       (one row)
```

A "wrap" is:

```
(kem_wrap_key, ss) = ML-KEM-1024.Encap(recipient_crypt_pkey)
wrapped_msg_key    = AES-256-GCM.encrypt(key: ss, plaintext: sender_msg_key)
# stored as (peer_kem_wrap_key_b64, peer_wrapped_msg_key_b64)
```

Unwrap:

```
ss         = ML-KEM-1024.Decap(own_crypt_skey, peer_kem_wrap_key_b64)
sender_msg_key  = AES-256-GCM.decrypt(key: ss, peer_wrapped_msg_key_b64)
```

---

## Tables

There is no `dialogs` table. Participation is derived from `dialog_keys` via `sender_hash = me OR peer_hash = me`, which is also the sync filter. Dialog existence is advisory; trust is in the signed rows below.

### 1. `dialog_keys`

Wrapped `sender_msg_key` published by one author for one dialog. Two rows per dialog in the common case (one per direction). An author republishes the same row idempotently from any of their devices (deterministic `sender_msg_key` ⇒ same plaintext, different KEM randomness ⇒ compatible).

| Column                     | Type               | Notes                                                                                           |
|----------------------------|--------------------|-------------------------------------------------------------------------------------------------|
| `dialog_hash`              | `dialog_hash_type` | PK part                                                                                         |
| `sender_hash`              | `user_hash_type`   | PK part; author of this `sender_msg_key`                                                             |
| `peer_hash`                | `user_hash_type`   | the other participant; enables sync filter and inbox listing without a separate `dialogs` table |
| `peer_kem_wrap_key_b64`    | `bytea`            | ML-KEM ciphertext to peer's `crypt_pkey`                                                        |
| `peer_wrapped_msg_key_b64` | `bytea`            | AES-GCM(sender_msg_key) with ss from `peer_kem_wrap_key_b64`                                         |
| `owner_timestamp`          | `integer`          | Monotonic counter; must increase on updates; prevents replay attacks                            |
| `delete_flag`              | `boolean`          | Soft delete marker; `true` indicates deleted                                                    |
| `sign_b64`                 | `bytea`            | ML-DSA-87 signature by `sender_hash` over canonical serialization of all preceding columns      |

PK: `(dialog_hash, sender_hash)`.

Self-authenticating per [02_integrity.md](../electric/pq_data_layer/02_integrity.md), same bootstrap as `user_cards`: fetch `user_cards` for `sender_hash`, verify its self-signature, then verify this row's `sign_b64` under that `sign_pkey`. A row with invalid `sign_b64` is rejected on ingest and re-verified on peer-sync receive. Because `dialog_hash`, `peer_hash`, and both KEM ciphertexts are all covered by the signature, no field can be rewritten, retargeted to a different peer, or lifted into a different dialog without detection.

Flooding: an attacker can still publish a row naming an uninvolved `peer_hash` (PoP proves submitter identity, not peer consent). Clients mitigate by hiding a dialog until the local user has either authored a message in it or the peer has published their own `dialog_keys` row for the same `dialog_hash`.



### 2. `dialog_messages`

Messages, ordered by `message_uuid` (UUID v7 — time-ordered). Versioned in place: an edit inserts a new row with the same `message_uuid` and higher `version`. Content is embedded, encrypted with `sender_msg_key`.

| Column | Type | Notes |
|---|---|---|
| `dialog_hash` | `dialog_hash_type` | PK part |
| `message_uuid` | `uuid` | PK part; UUID v7 |
| `version` | `integer` | PK part; starts at 0, increments on edit |
| `sender_hash` | `user_hash_type` | author |
| `content_type` | `text` | for polymorphic / embedded content |
| `content_nonce` | `bytea` | 12 bytes, AES-GCM nonce |
| `content_enc` | `bytea` | AES-256-GCM ciphertext of the payload |
| `sign_b64` | `bytea` | ML-DSA-87 signature by `sender_hash` over all preceding columns |

PK: `(dialog_hash, message_uuid, version)`.

### 3. `dialog_reactions`

Reactions bind to a specific message **version** via `message_sign_hash` — the SHA3-512 of the reacted-to row's `sign_b64`. Reacting to an edited message does not automatically carry over.

| Column | Type | Notes |
|---|---|---|
| `dialog_hash` | `dialog_hash_type` | PK part |
| `message_uuid` | `uuid` | PK part |
| `sender_hash` | `user_hash_type` | PK part; who reacted |
| `type` | `text` | PK part; reaction kind |
| `message_sign_hash` | `bytea` | SHA3-512 of the reacted message row's `sign_b64` |
| `sign_b64` | `bytea` | ML-DSA-87 signature by `sender_hash` over all preceding columns |

PK: `(dialog_hash, message_uuid, sender_hash, type)`.

---

## Flows

### Author sends a message

1. Compute `dialog_hash` from `(sender_hash, peer_hash)`.
2. Derive `sender_msg_key` (formula above).
3. If no `dialog_keys` row exists for `(dialog_hash, sender_hash)`: wrap `sender_msg_key` self + peer, sign, insert (row carries `peer_hash`).
4. Build message: fresh UUID v7, `version = 0`, AES-GCM encrypt content under `sender_msg_key`, sign, insert into `dialog_messages`.

### Peer reads

1. Fetch `dialog_keys` rows for `dialog_hash`.
2. For each row authored by a counterparty: verify `sign_b64` against `sender_hash`'s `sign_pkey`, then unwrap via `peer_kem_wrap_key_b64` / `peer_wrapped_msg_key_b64` using own `crypt_skey` ⇒ their `sender_msg_key`.
3. For messages authored by self: re-derive `sender_msg_key` from own private keys (deterministic derivation). (Or unwrap from a counterparty's `dialog_keys` row where self is the peer.)
4. For each `dialog_messages` row: verify `sign_b64`, AES-GCM decrypt `content_enc` under the matching author's `sender_msg_key`.

### Author on a new device

1. Device has the author's `sign_skey`, `kem_skey`, `contact_skey` (from User Identity, per `pq_user.md`).
2. Re-derive `sender_msg_key` — same value as on any other device.
3. Can read own past messages by re-deriving `sender_msg_key` from private keys (deterministic derivation).
4. To write: no new `dialog_keys` row needed (one already exists for `(dialog_hash, sender_hash)`); proceed to insert `dialog_messages`.

### Either side initiates independently

Both sides compute the same `dialog_hash`. Each inserts its own `dialog_keys` row keyed on its own `sender_hash`, naming the other as `peer_hash`. No coordination needed. A client listing inbox dialogs queries `dialog_keys WHERE sender_hash = me OR peer_hash = me`.

---

## Open questions

- **Read receipts** — separate table or boolean per recipient on `dialog_messages`?
- **Delete / retract** — new version with empty content, or a dedicated tombstone type?
- **Content polymorphism schema** — registry of `content_type` values and their plaintext envelopes.
- **Large content (attachments)** — inline `content_enc` vs. external blob referenced by hash.

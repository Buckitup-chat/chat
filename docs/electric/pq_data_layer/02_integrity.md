# Integrity

> Status: **solved** — every row in `user_cards` and `user_storage` is self-authenticating via `sign_b64`.

## Problem

Because writes propagate between peers without central arbitration (see [electric_network_sync.md](../../reqs/electric_network_sync.md)), a row's authenticity cannot depend on the server that served it. The row itself must prove it came from the legitimate owner, and any tampering with stored fields must be detectable by any consumer at any time.

## Approach

**Integrity is achieved by three fields — `deleted_flag`, `owner_timestamp`, `sign_b64` — carried by every signable PQ row.** Together they form the universal integrity triad; nothing else is required to make a row self-authenticating, replay-resistant, and deletion-safe.

| Field | Role |
|---|---|
| `deleted_flag` | Boolean under the signature — makes *deletion* a first-class, signed claim rather than an unauthenticated server-side op. A soft-delete is a newer signed row with `deleted_flag: true` and a higher `owner_timestamp`. |
| `owner_timestamp` | Monotonic counter chosen by the owner. Included in `sign_b64`, so it cannot be rewritten; used to reject replays and to order supersessions (a newer signed row with a higher `owner_timestamp` overrides an older one). |
| `sign_b64` | ML-DSA-87 signature over a canonical serialization of every other field in the row (including `deleted_flag` and `owner_timestamp`). Any mutation to any signed field invalidates it. |

These three fields are the universal contract — every signable PQ row includes them, and they are added together as one migration (`priv/repo/migrations/20260317071358_add_integrity_fields_to_user_cards.exs`). The signing key is the row owner's `sign_skey`; the verifying key (`sign_pkey`) is discoverable via the owner's `user_cards` row, which itself is self-signed.

Canonical serialization is alphabetical-by-key concatenation with per-type encoding (base64 for `_b64`/`_cert`/`_pkey` fields, `"true"`/`"false"` for booleans, `"null"` for nil, decimal for integers, raw UTF-8 for strings). See `Chat.Data.Integrity.signature_payload/1`.

Trust bootstrap:

1. A `user_cards` row binds `sign_pkey` to `user_hash` (where `user_hash = "u_" + hex(SHA3-512(sign_pkey))`). Anyone can re-hash `sign_pkey` and confirm the binding with zero external state.
2. `contact_pkey` and `crypt_pkey` are bound to that identity via `contact_cert` / `crypt_cert` — bare ML-DSA-87 signatures over the pubkey bytes, no X.509.
3. Every dependent row (e.g. `user_storage`) names its owner's `user_hash` and signs itself with the same `sign_skey` using the same triad, so verification is: fetch `user_cards` row → verify self-signature → use its `sign_pkey` to verify the dependent row.

## Where this lives

- **Field-level schema + algorithms**: [pq_user.md](../../reqs/pq_user.md)
- **Storage row integrity**: [pq_user_storage.md §3.1 / §5.2](../../reqs/pq_user_storage.md) (`sign_hash`, `sign_b64`)
- **Table layout**: [SCHEMAS.md](./SCHEMAS.md) — `user_cards` is the canonical example; `sign_b64`, `owner_timestamp`, `deleted_flag` all listed as `NOT NULL`.
- **Reference schema module**: `Chat.Data.Schemas.UserCard` — `@create_fields` includes the triad; `Signable` impl drops only `sign_b64` and `__meta__`, so every other field (including `owner_timestamp` and `deleted_flag`) is covered by the signature.
- **Verification primitive**: `Chat.Data.Integrity.verify_signature/1` (protocol-driven, same for every signable schema).
- **Where verification runs**: `validate/3` per-model ingestion callback — see [Electric_Abstraction_Layer.md](../Electric_Abstraction_Layer.md)

## Invariants

- A row without a valid `sign_b64` is indistinguishable from garbage — peers reject it on ingest and peer-sync consumers must re-verify on receive (peer writes bypass PoP but **not** signature validation).
- `owner_timestamp` is strictly monotonic per row key. An incoming update with `owner_timestamp <= existing` is rejected as a replay, even if its signature verifies.
- `deleted_flag` is never flipped outside a fresh signed row — deletes are as authenticated as creates. There is no server-side "delete" operation that bypasses the owner.
- `user_hash` is derived, never asserted — server never needs to trust a client's claim of who they are; it recomputes.
- Certificates (`contact_cert`, `crypt_cert`) are raw signatures, not wrapped structures. Anyone holding `sign_pkey` can verify without parsing ASN.1.

## Relationship to Proof-of-Possession

PoP proves *the submitter* controls the key at request time. Integrity proves *the row* was authored by the key holder at some point. Both are required:

- PoP alone: an attacker with a stale valid row could still submit it — integrity catches mismatches.
- Integrity alone: anyone holding a historical signed row could re-submit it — PoP (+ `owner_timestamp` monotonicity) prevents that.

## Open extensions

- Cross-table integrity (e.g. a `user_storage` row referring to a `user_card` that was later rotated).
- Signature versioning for algorithm migration (post-ML-DSA-87 successors).

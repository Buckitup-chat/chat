# PQ Origin

Origin entity for the review system — a subaccount identity that represents a business, venue, or
other entity people review.

## Origin

An origin is modeled as a **subaccount** — it gets its own `user_cards` row with a separate PQ identity.

An origin has:

- its own `user_cards` row (ML-DSA-87 signing keypair, ML-KEM-1024 encryption keypair)
- an owner (the user who created it)
- a moderation policy for public reviews
- public metadata (name, description — signed by origin identity)

The origin identity is separate from the owner's personal identity. One user can own multiple origins. Because it is a `user_cards` entry, the existing dialog infrastructure (see [pq_dialogs.done.md](../pq_dialogs.done.md)) works directly for `to_origin` communication.

### Origin creation

Three-step flow following the same pattern as user creation (see [pq_user.done.md](../pq_user.done.md)):

1. **Owner exists** — the creating user already has their own `user_cards` row
2. **Generate origin identity** — client generates independent ML-DSA-87 + ML-KEM-1024 keypairs for the origin, inserts a new `user_cards` row (self-signed by the origin's own `sign_skey`)
3. **Create origin row** — insert `origin` table row signed by the origin identity, with `owner_cert` proving the owner created this identity

The `owner_cert` is `ML-DSA-87.sign(origin_sign_pkey, owner_sign_skey)` — the owner signs the origin's public signing key, binding the origin identity to the owner. Same pattern as `crypt_cert` binds encryption key to identity.

Origin secret keys (`sign_skey`, `crypt_skey`) are generated independently (not derived from owner keys) and stored client-side. For multi-device access, the owner encrypts origin keys into User Storage, decryptable by the owner's own keys on other devices.

Two levels of control:

- **Owner** (the creating user) — performs dangerous/irreversible operations: create origin, delete, change moderation mode. Ownership is immutable after creation. Owner identity is never exposed to the public.
- **Origin identity** — handles day-to-day operations: receive `to_origin` reviews, moderate public reviews. Can be delegated to an employee without exposing the owner's personal identity or granting irreversible powers.

> **Status (deferred to Phase 3).** The two-tier split is not fully enforced. Origin `update` operations — including
> `moderation_mode` changes and soft delete (`deleted_flag`) — currently accept **either** the origin identity's
> **or** the owner's signature ([`Origin.Validation.validate_origin_update_signature/1`](../../../../lib/chat/data/origin/validation.ex):87).
> A delegated origin-identity holder can therefore perform dangerous ops. Requiring the **owner's** signature
> exclusively for these operations lands with the Phase 3 owner/moderation UI. `owner_cert` is still verified on
> origin creation.

### Pending-review guard on origin modification

[`Origin.Validation.owner_auth/2`](../../../../lib/chat/data/origin/validation.ex) rejects HTTP origin updates when reviews are pending moderation — [`has_pending_reviews?/1`](../../../../lib/chat/data/origin/validation.ex):56 checks for reviews that have no `review_public_passwords` entry. This prevents moderation-mode changes while reviews are mid-pipeline (e.g. switching from `pre` to `none` while a review awaits approval).

### Why not a room

Rooms are conversation spaces. Origins are entities people review. They share crypto infrastructure but have different semantics:

- rooms have members who chat; origins have reviewers who evaluate
- room membership is about participation; origin visibility is about trust tiers
- rooms don't need moderation workflows; origins do
- the review/comment hierarchy doesn't map to room message threading

Keeping them separate avoids overloading the room model and allows independent evolution.

## Data model

### origin

The origin identity lives in `user_cards` (its own `user_hash`, `sign_pkey`, `crypt_pkey`). The [`origin`](../../../../lib/chat/data/schemas/origin.ex) table holds origin-specific metadata that doesn't belong in `user_cards`.

```
origins                                              — DB table name
├── origin_hash           — TEXT PK, FK → user_cards(user_hash), the origin's user_hash
├── owner_hash            — TEXT NOT NULL, FK → user_cards(user_hash), user_hash of the owner
├── owner_cert            — BYTEA NOT NULL, ML-DSA-87.sign(origin_sign_pkey, owner_sign_skey)
├── name                  — TEXT NOT NULL, origin name (signed by origin identity)
├── moderation_mode       — TEXT NOT NULL DEFAULT 'none', enum: none / post / pre
├── deleted_flag          — BOOLEAN NOT NULL DEFAULT false, soft delete by owner
├── owner_timestamp       — BIGINT NOT NULL, causal ordering (LWW)
├── sign_b64              — BYTEA NOT NULL, origin identity's ML-DSA-87 signature over all fields
└── sign_hash             — TEXT NOT NULL, prefix "ors_" + hex(SHA3-512 of sign_b64)
```

Constraints: `origin_hash` and `owner_hash` match `^u_[a-f0-9]{128}$`, `sign_hash` matches `^ors_[a-f0-9]{128}$`, `moderation_mode` IN (`none`, `post`, `pre`). Index on `owner_hash`.

Migration: [`20260715144320_create_origins`](../../../../priv/repo/migrations/20260715144320_create_origins.exs), Electric publication: [`20260715144321`](../../../../priv/repo/migrations/20260715144321_add_origins_to_electric_publication.exs).

Note: `sign_pkey` and `crypt_pkey` are on the origin's `user_cards` row, not duplicated here. The origin's `user_cards` row is self-signed (origin signs its own card with `origin_sign_skey`). The `owner_cert` on the `origin` row binds the origin identity to the owner.

## Electric shape

Shape: [`Chat.Data.Shapes.Origin`](../../../../lib/chat/data/shapes/origin.ex). Synced to everyone — public directory of origins.

Access control: insert requires origin identity auth; update requires owner auth (with [`has_pending_reviews?/1`](../../../../lib/chat/data/origin/validation.ex) guard).

## Source modules

| Layer | Module | Source |
|-------|--------|--------|
| Schema | `Chat.Data.Schemas.Origin` | [`schemas/origin.ex`](../../../../lib/chat/data/schemas/origin.ex) |
| Validation | `Chat.Data.Origin.Validation` | [`origin/validation.ex`](../../../../lib/chat/data/origin/validation.ex) |
| Data context | `Chat.Data.Origin` | [`origin.ex`](../../../../lib/chat/data/origin.ex) |
| Types | `OriginSignHash` | [`types/origin_sign_hash.ex`](../../../../lib/chat/data/types/origin_sign_hash.ex) |

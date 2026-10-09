# PQ Review Write Tokens

One-time links that lead a user to writing a review for a given origin.

## Goal

An origin owner generates a short URL (printable as QR, shareable via NFC/text/email) that, when opened, guides the visitor through identity creation (or import) and into writing a review for that specific origin. The token is one-time — once bound to a reviewer, it becomes a permanent redirect to that reviewer's review.

---

## Token Lifecycle

A write token progresses through three states:

| State | `user_hash` | `review_hash` | `deleted_flag` | Behavior on visit |
|-------|-------------|---------------|----------------|-------------------|
| **pending** | null | null | false | Identity gate → bind → review form |
| **bound** | set | null | false | Review form (same user) / 403 (different user) |
| **reviewed** | set | set | false | Redirect to review (view/edit) |
| **soft-deleted** | null | null | true | "This link has expired" |

```
pending  ──visit──▶  identity gate  ──PoP──▶  bound  ──submit──▶  reviewed
   │                                            │                      │
   │ 1 week                                bind wins LWW          permanent link
   ▼                                    (bot clock >> ts+1)       to author's review
soft-deleted  ──2 weeks──▶  hard delete (row removed)
```

Tokens that remain **pending** for 1 week (bot clock) are **soft-deleted** (`deleted_flag = true`, `owner_timestamp` set to original `owner_timestamp + 1`). The minimal timestamp bump ensures a concurrent bind on another device — which uses the bot's current clock, far higher — wins LWW. Soft-deleted tokens are **hard-deleted** 2 weeks after soft delete (3 weeks after creation). Bound and reviewed tokens persist indefinitely — they are permanent links.

---

## Trust Delegation

Write tokens are authorized through a vouch chain rooted in the [vouch tokens](../pq_vouch_tokens.in_progress.md) system.

### Review bot vs syncBot

The server-level syncBot handles synchronization only — it is not involved in review delegation. Review bots are separate, per-origin entities.

### Review bot identity

Each origin gets its own **review bot** — a PQ entity with its own `user_cards` row and full identity (ML-DSA-87 + ML-KEM-1024 keypairs). The review bot is created alongside the origin (or when the owner enables review invitations). Its `sign_pkey` is public via `user_cards`, so anyone can verify its vouch tokens.

The bot's `user_cards` row uses the name `<originName>_Bot` — visible in the user directory, clearly associated with its origin.

One review bot per origin. No cross-origin leakage by construction — the bot exists only in the context of its origin.

### Origin bot storage — `origin_bots` table

The bot's full identity (both keypairs' secret keys) is encrypted to the origin's `crypt_pkey` and stored in the `origin_bots` table. This table is **Electric-synced** — any device holding the origin's `crypt_skey` can decrypt the bot identity and start a bot GenServer. The server never sees the bot's secret keys in cleartext.

```
origin_bots
├── origin_hash         — TEXT PK, FK → origins(origin_hash)
├── bot_hash            — TEXT NOT NULL, FK → user_cards(user_hash), prefix "u_"
├── encrypted_identity  — BYTEA NOT NULL (bot's full identity, ML-KEM encrypted to origin's crypt_pkey)
├── owner_timestamp     — BIGINT NOT NULL (origin clock, LWW)
├── sign_b64            — BYTEA NOT NULL (signed by origin identity)
├── sign_hash           — TEXT NOT NULL, prefix "ob_"
```

**`encrypted_identity`** contains the bot's `sign_skey` + `crypt_skey` — everything needed to operate as the bot. Encrypted using ML-KEM-1024 encapsulation to the origin's `crypt_pkey`. Same pattern as origin keys in User Storage for multi-device access.

**Device startup flow:**
1. Device syncs `origin_bots` shape (filtered by origins this device holds keys for)
2. For each origin bot: ML-KEM decapsulate `encrypted_identity` with origin's `crypt_skey`
3. Start `ReviewBotWorker` GenServer with the decrypted identity
4. Bot can now create tokens, issue vouches, GC — all on the device

The bot runs **on the origin owner's device** (or Nerves hardware), not on the server. Token creation and vouch issuance happen device-side, hitting `/ingest` the same way all other PQ rows do.

### Vouch chain

The origin owner vouches the review bot directly:

```
Origin owner
  │
  │  Vouch token:
  │    kind:         origins.<origin_hash>.reviews.write
  │    issuer_hash:  origin_hash
  │    subject_hash: review_bot_hash
  │    sign_b64:     signed with origin's sign_skey (client-side)
  │
  ▼
Review bot (per-origin, device-side, identity in origin_bots encrypted to origin)
```

**Origin → review bot:** The origin owner signs this vouch from their client using the origin's `sign_skey`. This is a deliberate step in the origin admin UI — the owner explicitly enables review invitations for their origin, which creates the review bot (if it doesn't exist) and vouches it.

### Bot → reviewer delegation

On token bind, the review bot creates a vouch token:

```
kind:         origins.<origin_hash>.reviews.write.<nonce>
issuer_hash:  review_bot_hash
subject_hash: reviewer_hash
sign_b64:     signed with review bot's sign_skey
```

Attenuation holds: `reviews.write.<nonce>` is prefix-contained by `reviews.write` (see [Scope Attenuation](../pq_vouch_tokens.in_progress.md#scope-attenuation)).

The full verifiable chain: origin vouched review bot → review bot delegated to reviewer → reviewer wrote the review (ML-DSA-87 signed). Any peer can walk this chain using only public keys from `user_cards` and the vouch token rows.

---

## URL Format

```
https://<host>/r/<nonce>
```

`<nonce>` is 24 random bytes, URL-safe base64 encoded (32 characters). Short enough for QR codes and NFC payloads. The full URL is the QR payload — no app-specific scanner required.

---

## Schema

### review_write_tokens

Electric-synced table with integrity triad. **Device-transparent** — any device running the origin's review bot can read and manage tokens. The durable trust proof is the vouch token in the PQ `vouch_tokens` table; this table handles token lifecycle and redirect logic.

Tokens are created by the review bot on the device when an order is opened. Every token is tied to an order — there are no unassigned tokens.

```
review_write_tokens
├── nonce              — TEXT PK (URL-safe base64, 32 chars)
├── origin_hash        — TEXT NOT NULL, FK → origins(origin_hash)
├── origin_order_hash  — TEXT NOT NULL, prefix "org_ord_" (the order that triggered this token)
├── user_hash          — TEXT, nullable (null = pending; set = bound)
├── review_hash        — TEXT, nullable (set once review is written)
├── vouch_sign_hash    — TEXT, nullable (sign_hash of the vouch token created on bind)
├── deleted_flag       — BOOLEAN NOT NULL DEFAULT false (soft-delete marker)
├── owner_timestamp    — BIGINT NOT NULL (bot clock, LWW)
├── sign_b64           — BYTEA NOT NULL (signed by review bot's sign_skey)
├── sign_hash          — TEXT NOT NULL, prefix "rwt_"
```

**`origin_order_hash`** — NOT NULL. A token exists because an order was opened. The hash uses the `org_ord_` prefix. The orders table design is deferred — this is a forward reference to whatever that table becomes.

**`owner_timestamp`** — bot monotonic clock, same convention as `owner_timestamp` elsewhere. The bot owns these rows and GCs against its own timeline.

**`sign_b64` + `sign_hash`** — integrity triad. The review bot signs every token row (create, bind, review-hash capture, GC tombstone). Any device holding the bot identity can verify and update tokens.

**No `max_uses`** — tokens are one-time. One nonce, one reviewer, one review.

**No `expires_at`** — expiry is implicit: the bot GCs pending tokens older than its threshold. Bound tokens never expire.

**Electric shape** — devices filter by origins they hold keys for. Any device that starts its `ReviewBotWorker` sees all tokens for that origin and can create, bind, or GC them. Multiple devices creating tokens simultaneously is conflict-free (random nonces as PKs).

Indexes: `origin_hash` (list tokens per origin), `origin_order_hash` (lookup by order), `user_hash` (lookup by reviewer).

---

## Endpoints

### API

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /api/origins/:origin_hash/open_order` | Origin owner | Open order → bot creates token, returns nonce + URL |
| `POST /api/write_tokens/:nonce/bind` | Authenticated (PoP) | Bind user to token → bot issues vouch → redirect to review creation |
| `GET /api/origins/:origin_hash/write_tokens` | Origin owner | List active tokens for this origin |
| `DELETE /api/origins/:origin_hash/write_tokens/:nonce` | Origin owner / bot | Revoke (delete) a token |

### Route

```
/r/:nonce → FrontendController, :write_review
```

Phoenix checks token state and redirects:

```
GET /r/:nonce
  ├── not found / soft-deleted   → "This link has expired"
  ├── bound to different user    → "This link was already used"
  ├── bound to current user,
  │   review exists              → redirect to review (view/edit)
  ├── bound to current user,
  │   no review yet              → redirect to review creation for this origin
  └── pending                    → redirect to frontend with nonce context
                                   (frontend handles identity create/import,
                                    then calls /bind)
```

The existing frontend handles identity creation, review writing, and the full review pipeline. No separate SPA flow needed.

### Open order (token creation)

`POST /api/origins/:origin_hash/open_order`:

1. Verify caller is origin owner
2. Bot generates nonce (24 random bytes, URL-safe base64)
3. Bot constructs token row with `origin_order_hash` (required), signs it
4. Bot ingests via `POST /ingest` — server validates bot signature + live vouch
5. Returns nonce + full URL (`https://<host>/r/<nonce>`) for QR generation

Requires a live vouch: `kind = origins.<origin_hash>.reviews.write`, `issuer_hash = origin_hash`, `subject_hash = review_bot_hash`, `deleted_flag = false`. If no live vouch, rejects.

### Token bind

`POST /api/write_tokens/:nonce/bind`:

1. Validate the token is pending (not bound, not soft-deleted)
2. Verify the caller's identity: `user_cards` row exists with valid self-signature (PoP)
3. Verify the origin's review bot holds a live `reviews.write` vouch for this origin
4. Review bot creates vouch token `origins.<origin_hash>.reviews.write.<nonce>` for the reviewer
5. Bot updates token record: `user_hash`, `vouch_sign_hash`, `owner_timestamp = bot_clock` (current bot time, always >> ts+1), re-signs, ingests
6. Redirect to frontend review creation for this origin

### Review ingest validation

When `review_access = invite_only`, review ingest checks that the author holds a live vouch token where `subject_hash = author_hash` and `kind` attenuates from `origins.<origin_hash>.reviews.write`. No vouch = ingest rejected. This applies regardless of how the review is submitted — the vouch is the gate, not the token.

### Review hash capture

When the bot observes (via Electric shape) a new review for `(origin_hash, author_hash)` matching a bound token, it updates the token's `review_hash`, signs the updated row, and ingests it. This connects the token to its review for future redirects. Any device running the bot can perform this capture.

### Garbage collection

The review bot GCs its own tokens using `owner_timestamp` (bot clock), not server time:

Two-phase GC, both device-side in the `ReviewBotWorker`:

**Phase 1 — soft delete (1 week after creation):**
- Bot scans tokens where `user_hash IS NULL AND deleted_flag = false AND owner_timestamp < bot_clock - 1_week`
- Sets `deleted_flag = true`, `owner_timestamp = original_owner_timestamp + 1`, re-signs
- The `+1` bump is intentionally minimal: if another device bound the token concurrently (using its bot clock, far higher), the bind wins LWW
- Ingests via `/ingest`

**Phase 2 — hard delete (2 weeks after soft delete, 3 weeks after creation):**
- Bot scans tokens where `deleted_flag = true AND owner_timestamp < bot_clock - 3_weeks`
- Hard deletes the row (DELETE via `/ingest`)

Multiple devices may race to GC the same token — idempotent (same nonce PK, LWW on `owner_timestamp`). Bound and reviewed tokens are never GC'd.

---

## Origin Admin UI: "Enable Review Invitations"

A step in the origin admin interface where the owner creates the origin's review bot and delegates write scope to it. Everything happens client-side (or on the Nerves device) — the server only receives PQ rows via `/ingest`.

1. Owner opens origin settings
2. Clicks "Enable review invitations"
3. Client creates the review bot identity:
   - Generate ML-DSA-87 `sign_skey` / `sign_pkey` keypair
   - Generate ML-KEM-1024 `crypt_skey` / `crypt_pkey` keypair
   - Create `user_cards` row for the bot, named `<originName>_Bot` (self-signed by bot's `sign_skey`)
   - POST `/ingest` — bot's `user_cards` enters the PQ system
4. Client encrypts bot's full identity (`sign_skey` + `crypt_skey`) to the origin's `crypt_pkey` via ML-KEM encapsulation
5. Client creates `origin_bots` row with `encrypted_identity`, signed by origin identity
6. POST `/ingest` — `origin_bots` row enters the PQ system, Electric-synced to all devices holding this origin
7. Client constructs vouch token:
   - `kind: origins.<origin_hash>.reviews.write`
   - `issuer_hash: origin_hash`
   - `subject_hash: review_bot_hash`
   - Signs with origin's `sign_skey` (held client-side)
8. POST `/ingest` — vouch token enters the PQ system
9. Device decrypts `encrypted_identity`, starts `ReviewBotWorker` — the bot is live

On other devices: Electric syncs the `origin_bots` row → device decrypts with origin's `crypt_skey` → starts its own `ReviewBotWorker`. Multiple devices can run the bot simultaneously — token creation uses random nonces so there are no conflicts.

Revoking: the owner can revoke the review bot's vouch (signed tombstone, `deleted_flag: true`). Existing bound tokens remain valid (the vouch for the individual reviewer is already issued), but no new tokens can be created.

---

## Relationship to Existing Systems

### Review pipeline — unchanged

The vouch token gates entry (when `review_access = invite_only`). Once the reviewer has identity + vouch, they use the standard pipeline via the existing frontend: review → candidate → promotion → rights. The origin's `moderation_mode` applies as usual. The write token is the delivery mechanism for the vouch — the vouch itself is the permission.

### Vouch tokens — consumer

Write tokens consume the vouch token infrastructure for trust delegation. The `origins.<origin_hash>.reviews.write.<nonce>` scope sits in the origins subtree of the [Resource Forest](../pq_vouch_tokens.in_progress.md#resource-forest).

### Review access mode — per-origin policy

The origin owner decides whether reviews are open or invitation-only. A new field on the `origins` table:

| `review_access` | Behavior |
|-----------------|----------|
| `open` (default) | Anyone with an identity can write a review. Write tokens are optional (provenance, not gate). |
| `invite_only` | Review ingest requires a vouch in `origins.<origin_hash>.reviews.write.*` scope. No vouch = rejected. |

**Enforcement at ingest.** When `review_access = invite_only`, `Review.Validation` checks for a live (non-tombstoned) vouch token where `subject_hash = author_hash` and `kind` attenuates from `origins.<origin_hash>.reviews.write`. This covers both bot-delegated tokens (`reviews.write.<nonce>`) and any direct vouches.

**Mode change with existing reviews.** Switching from `open` to `invite_only` does not retroactively affect existing reviews — they are already in the pipeline. Only new review submissions are gated. Switching from `invite_only` to `open` is immediate.

**Relationship to moderation.** `review_access` controls who can *enter* the pipeline. `moderation_mode` controls what happens *inside* the pipeline. They are orthogonal — an `invite_only` origin can still run `pre` moderation on invited reviews.

---

## Origin Schema Change

A new column on the `origins` table:

```
origins
├── ...existing columns...
├── review_access        — TEXT NOT NULL DEFAULT 'open', enum: open / invite_only
```

Migration adds the column. Constraint: `review_access IN ('open', 'invite_only')`. Covered by the origin identity's signature (added to `Signable` fields). Changing `review_access` follows the same update path as `moderation_mode` — signed by origin identity or owner, subject to the pending-review guard.

---

## Implementation Phases

### Phase 1 — Origin bot + token infrastructure

- [ ] `origin_bots` migration + Ecto schema + Electric shape
- [ ] `OriginBotSignHash` type, `ob_` prefix in Consts
- [ ] `ReviewWriteTokenSignHash` type, `rwt_` prefix in Consts
- [ ] `OriginOrderHash` type, `org_ord_` prefix in Consts
- [ ] Bot creation flow: keypair gen, `user_cards` row (`<originName>_Bot`), identity encryption, `origin_bots` ingest
- [ ] Bot vouch: origin → bot vouch token (`origins.<origin_hash>.reviews.write`)
- [ ] `ReviewBotWorker` GenServer: decrypt identity from `origin_bots` shape, start on sync
- [ ] `review_access` column on `origins` + migration
- [ ] `review_access` in Origin schema, validation, Signable
- [ ] Review ingest: vouch check when `review_access = invite_only`

### Phase 2 — Token CRUD + redirect

- [ ] `review_write_tokens` migration (with `origin_order_hash` NOT NULL, integrity triad, `deleted_flag`) + Electric shape
- [ ] `ReviewWriteToken` Ecto schema
- [ ] `POST /api/origins/:origin_hash/open_order` — bot creates token on order open
- [ ] `POST /api/write_tokens/:nonce/bind` — bind user with PoP, bot issues vouch, redirect to frontend
- [ ] Token listing/deletion endpoints
- [ ] `/r/:nonce` Phoenix route — token state check + redirect to frontend
- [ ] Bot-side two-phase GC (soft delete at 1 week, hard delete at 3 weeks)
- [ ] Review ingest validation: vouch check when `review_access = invite_only`
- [ ] Origin admin: "enable invitations" UI (triggers Phase 1 bot creation + vouch)

### Phase 3 — QR

- [ ] QR code generation (frontend, from full URL)
- [ ] Printable QR sheet (multiple tokens per page)

---

## Open Questions

1. ~~**Review bot storage.**~~ — resolved. Bot identity stored in `origin_bots` table, encrypted to origin's `crypt_pkey`, Electric-synced across devices. See [Origin bot storage](#origin-bot-storage--origin_bots-table).

2. ~~**Token metadata for QR.**~~ — resolved. Token metadata lives on the order (`origin_order_hash`). The orders table design is deferred, but the link from token to order is established.

3. **Orders table.** `origin_order_hash` is a forward reference — the table that backs it is not yet designed. Until then, the hash is an opaque tag the bot stamps on each token. Schema, lifecycle, and what metadata an order carries (table number, event name, etc.) are out of scope for this document.

---

## Status

Proposed.

## References

- [pq_vouch_tokens](../pq_vouch_tokens.in_progress.md) — vouch token system, resource forest, attenuation
- [pq_reviews](pq_reviews.in_progress.md) — review system overview, pipeline, sandboxes
- [pq_review_moderation](pq_review_moderation.done.md) — moderation pipeline, candidate promotion
- [pq_origin](pq_origin.done.md) — origin entity, creation, ownership
- [pq_review_versioning](pq_review_versioning.done.md) — review editing, version chain

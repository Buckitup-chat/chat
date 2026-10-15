# PQ Review Write Tokens

Links that lead a user to writing a review for a given origin.

## Goal

An origin owner generates a short URL (printable as QR, shareable via NFC/text/email) that, when opened, guides the visitor through identity creation (or import) and into writing a review for that specific origin. Tokens come in two modes: **order-linked** (one-time — once bound to a reviewer, it becomes a permanent redirect to that reviewer's review) and **reusable** (a standing invitation link that can bind many reviewers, each getting their own bound token copy).

---

## Token Lifecycle

A write token progresses through these states:

| State | `user_hash` | `review_hash` | `deleted_flag` | `parent_nonce` | Behavior on visit |
|-------|-------------|---------------|----------------|----------------|-------------------|
| **pending** | null | null | false | null | Identity gate → bind → review form |
| **bound** | set | null | false | null or set | Review form (same user) / 403 (different user) |
| **reviewed** | set | set | false | null or set | Redirect to review (view/edit) |
| **soft-deleted** | null | null | true | null | "This link has expired" |

`parent_nonce` is null on order-linked tokens and on the reusable parent. It is set on bound copies created from a reusable parent.

```
                    ┌─────────── order-linked (origin_order_hash set) ───────────┐
                    │                                                            │
pending  ──visit──▶ │ identity gate  ──PoP──▶  bound  ──submit──▶  reviewed     │
   │                │                            │                      │        │
   │                │                       bind wins LWW          permanent     │
   │                │                    (bot clock >> ts+1)       link          │
   │                └────────────────────────────────────────────────────────────┘
   │
   │                ┌─────────── reusable (origin_order_hash null) ──────────────┐
   │                │                                                            │
   ├──visit──▶      │ identity gate  ──PoP──▶  NEW bound token (fresh nonce,    │
   │                │                           parent_nonce = this nonce)       │
   │                │                           original stays pending           │
   │                └────────────────────────────────────────────────────────────┘
   │
   │ ttl_days (bot, default 7)
   ▼
soft-deleted  ──2 weeks (server)──▶  hard delete (row removed)
```

Tokens that remain **pending** for `review_token_ttl_days` (default 7, configurable per origin in `origin_settings`) are **soft-deleted** by the bot (`deleted_flag = true`, `owner_timestamp` set to original `owner_timestamp + 1`). The minimal timestamp bump ensures a concurrent bind on another device — which uses the bot's current clock, far higher — wins LWW. Soft-deleted tokens are **hard-deleted** by the server 2 weeks after soft delete. Bound and reviewed tokens persist indefinitely — they are permanent links.

---

## Trust Delegation

Write tokens are authorized through a vouch chain rooted in the [vouch tokens](../pq_vouch_tokens.in_progress.md) system.

### Review bot vs syncBot

The server-level syncBot handles synchronization only — it is not involved in review delegation. Review bots are separate, per-origin entities.

### Review bot identity

Each origin gets its own **review bot** — a PQ entity with its own `user_cards` row and full identity (ML-DSA-87 + ML-KEM-1024 keypairs). The review bot is created alongside the origin (or when the owner enables review invitations). Its `sign_pkey` is public via `user_cards`, so anyone can verify its vouch tokens.

The bot's `user_cards` row uses the name `ReviewBot_<originName>` — visible in the user directory, clearly associated with its origin.

Ideally one review bot per origin, but multiple are tolerated (device fragmentation — each device may independently create a bot if it hasn't synced the existing one yet). No cross-origin leakage by construction — each bot exists only in the context of its origin.

### Origin bot storage — `origin_bots` table

The bot's full identity (both keypairs' secret keys) is encrypted to the origin's `crypt_pkey` and stored in the `origin_bots` table. This table is **Electric-synced** — any device holding the origin's `crypt_skey` can decrypt the bot identity and start a bot GenServer. The server never sees the bot's secret keys in cleartext.

```
origin_bots
├── origin_hash         — TEXT NOT NULL, FK → origins(origin_hash)
├── bot_hash            — TEXT PK, FK → user_cards(user_hash), prefix "u_"
├── secret_b64          — BYTEA NOT NULL (ML-KEM-1024 ciphertext — encapsulated shared secret)
├── encrypted_identity_b64 — BYTEA NOT NULL (AES-256-GCM blob — bot's sign_skey + crypt_skey)
├── deleted_flag        — BOOLEAN NOT NULL DEFAULT false (soft-delete / revoke)
├── owner_timestamp     — BIGINT NOT NULL (origin clock, LWW)
├── sign_b64            — BYTEA NOT NULL (signed by origin identity)
├── sign_hash           — TEXT NOT NULL, prefix "ob_"
```

**`secret_b64` + `encrypted_identity_b64`** — two-field KEM wrap, same pattern as `dialog_keys` (`peer_kem_wrap_key_b64` + `peer_wrapped_msg_key_b64`). `secret_b64` holds the ML-KEM-1024 ciphertext; `encrypted_identity_b64` holds the AES-256-GCM blob containing the bot's `sign_skey` + `crypt_skey`. Produced by `EnigmaPq.kem_encrypt/3`, unwrapped by `EnigmaPq.kem_decrypt/4` with salt `"buckitup/origin-bot/v1"`.

**Device startup flow:**
1. Device syncs `origin_bots` shape (filtered by origins this device holds keys for)
2. For each origin bot: `identity = EnigmaPq.kem_decrypt(secret_b64, encrypted_identity_b64, origin_crypt_skey, "buckitup/origin-bot/v1")`
3. Start `ReviewBotWorker` GenServer with the decrypted identity
4. Bot can now create tokens, issue vouches, GC — all on the device

The bot runs **on the origin owner's device** (or Nerves hardware), not on the server. Token creation and vouch issuance happen device-side, hitting `/ingest` the same way all other PQ rows do.

### Vouch chain

The origin owner vouches the review bot in both trees — origin scope for review authorization, device scope for write access to the shapes the reviewer will need:

```
Origin owner (also device owner)
  │
  │  Vouch 1 (origin gate):
  │    kind:         origins.<origin_hash>.reviews.write
  │    issuer_hash:  origin_hash
  │    subject_hash: review_bot_hash
  │    sign_b64:     signed with origin's sign_skey (client-side)
  │
  │  Vouch 2 (device gate):
  │    kind:         device.<sn>.storage.write.<review_shapes>
  │    issuer_hash:  owner_hash
  │    subject_hash: review_bot_hash
  │    sign_b64:     signed with owner's sign_skey (client-side)
  │
  ▼
Review bot (per-origin, device-side, identity in origin_bots encrypted to origin)
```

**Origin → review bot (vouch 1):** The origin owner signs this vouch from their client using the origin's `sign_skey`. This is a deliberate step in the origin admin UI — the owner explicitly enables review invitations for their origin, which creates the review bot (if it doesn't exist) and vouches it.

**Owner → review bot (vouch 2):** The device owner delegates write access to the specific shapes the reviewer needs (reviews, review candidates, etc.). Without this vouch, the reviewer's data would be rejected by the device gate even with a valid origin vouch. The owner signs this with their own `sign_skey` — the device tree is rooted in the owner, not the origin.

### Bot → reviewer delegation

On token bind, the review bot creates two vouch tokens — one per gate:

```
Vouch 1 (origin gate):
  kind:         origins.<origin_hash>.reviews.write.<nonce>
  issuer_hash:  review_bot_hash
  subject_hash: reviewer_hash
  sign_b64:     signed with review bot's sign_skey

Vouch 2 (device gate):
  kind:         device.<sn>.storage.write.<review_shapes>
  issuer_hash:  review_bot_hash
  subject_hash: reviewer_hash
  sign_b64:     signed with review bot's sign_skey
```

Attenuation holds in both trees: `reviews.write.<nonce>` is prefix-contained by `reviews.write`; `storage.write.<review_shapes>` is prefix-contained by the bot's own device write scope (see [Scope Attenuation](../pq_vouch_tokens.in_progress.md#scope-attenuation)). The bot cannot delegate wider than what it was granted.

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
├── review_bot_hash    — TEXT NOT NULL, FK → user_cards(user_hash), prefix "u_" (signer — Signable lookup key)
├── origin_order_hash  — TEXT, nullable, prefix "org_ord_" (the order that triggered this token; null = reusable invitation)
├── parent_nonce       — TEXT, nullable (set on bound copies of a reusable token; points to the parent's nonce)
├── user_hash          — TEXT, nullable (null = pending; set = bound)
├── review_hash        — TEXT, nullable (set once review is written)
├── deleted_flag       — BOOLEAN NOT NULL DEFAULT false (soft-delete marker)
├── owner_timestamp    — BIGINT NOT NULL (bot clock, LWW)
├── sign_b64           — BYTEA NOT NULL (signed by review bot's sign_skey)
├── sign_hash          — TEXT NOT NULL, prefix "rwt_"
```

**`origin_order_hash`** — nullable. When set (prefix `org_ord_`), the token is order-linked and one-time. When null, the token is a reusable invitation link — binding creates a new bound token row instead of modifying this one. The orders table design is deferred — when present, the hash is an opaque client-generated identifier with no FK constraint.

**`owner_timestamp`** — bot monotonic clock, same convention as `owner_timestamp` elsewhere. The bot owns these rows and GCs against its own timeline.

**`review_bot_hash`** — identifies the signing bot. The `Signable` protocol uses this to look up the bot's `sign_pkey` from `user_cards` — same direct-lookup pattern as `author_hash` on reviews and `issuer_hash` on vouch tokens.

**`sign_b64` + `sign_hash`** — integrity triad. The review bot signs every token row (create, bind, review-hash capture, GC tombstone). Any device holding the bot identity can verify and update tokens.

**`parent_nonce`** — nullable. Set on bound tokens created from a reusable (order-less) parent. Points to the original pending token's nonce. Null on order-linked tokens and on the reusable parent itself.

**No `max_uses`** — order-linked tokens are one-time: one nonce, one reviewer, one review. Reusable tokens (null `origin_order_hash`) can bind many reviewers — each bind produces a new token row with its own nonce and `parent_nonce` pointing back to the reusable parent.

**No `expires_at`** — expiry is implicit: the bot GCs pending tokens older than its threshold. Bound tokens never expire.

**Electric shape** — devices filter by origins they hold keys for. Any device that starts its `ReviewBotWorker` sees all tokens for that origin and can create, bind, or GC them. Multiple devices creating tokens simultaneously is conflict-free (random nonces as PKs).

Indexes: `origin_hash` (list tokens per origin), `origin_order_hash` (lookup by order), `user_hash` (lookup by reviewer).

---

## Endpoints

### API

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /r/api/token/create` | AuthToken (origin → bot) | Create token (with or without order), returns nonce + URL |
| `POST /r/api/token/bind` | Reviewer (PoP) | Bind user to token → bot issues vouches → redirect to review nonce page |

Token listing and deletion flow through Electric shapes + ingest (no REST endpoints).

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
  └── pending                    → login-kind landing page
                                   (identity create/import → PoP → /bind
                                    → redirect to review nonce page)
```

The existing frontend handles identity creation, review writing, and the full review pipeline. No separate SPA flow needed.

### Token creation

`POST /r/api/token/create`:

1. Verify caller via AuthToken — a token encrypted by the origin for the bot (not PoP)
2. Bot generates nonce (24 random bytes, URL-safe base64)
3. Bot constructs token row — `origin_order_hash` is optional (null = reusable invitation link), signs it
4. Bot ingests via `POST /ingest` — server validates bot signature + live vouch
5. Returns nonce + full URL (`https://<host>/r/<nonce>`) for QR generation

Requires a live vouch: `kind = origins.<origin_hash>.reviews.write`, `issuer_hash = origin_hash`, `subject_hash = review_bot_hash`, `deleted_flag = false`. If no live vouch, rejects.

### Token bind

Binding is a multi-step browser flow, not a single API call:

1. **Landing** — visitor opens `/r/:nonce`, gets a login-kind page
2. **Identity** — visitor creates a new identity or imports an existing one
3. **Bind** — visitor proves PoP (signs challenge with `sign_skey`) to `POST /r/api/token/bind`
4. **Redirect** — on success, redirect to origin review (nonce) create/edit page

`POST /r/api/token/bind` (step 3):

1. Validate the token exists and is not soft-deleted
2. Verify the caller's identity: `user_cards` row exists with valid self-signature (PoP)
3. Verify the origin's review bot holds live vouches: `origins.<origin_hash>.reviews.write` (origin gate) and per-shape device gate vouches (`device.<sn>.storage.write.<shape>` for each of: `review`, `review_password_candidate`, `review_post_right_candidate`, `review_revoke_right_candidate`)
4. Review bot creates per-shape vouch tokens for the reviewer: `origins.<origin_hash>.reviews.write.<nonce>` (origin gate) and `device.<sn>.storage.write.<shape>` for each required shape (device gate)
5. **Order-linked token** (`origin_order_hash` set): bot updates the token row — sets `user_hash`, `owner_timestamp = bot_clock`, re-signs, ingests. Token is now one-time bound.
6. **Reusable token** (`origin_order_hash` null): bot creates a NEW token row with a fresh nonce, `parent_nonce = original_nonce`, `user_hash = reviewer_hash`, `origin_order_hash = null`, signs and ingests. The original pending token stays untouched for more binds.
7. Redirect to origin review (nonce) create/edit page

### Review ingest validation

Review ingest passes through two independent gates — both must succeed:

1. **Device gate** (`device.<sn>.storage.write`) — the standard write gate. The review is a PQ row hitting `/ingest` on a device; the device's access mode (`guarded` / `trust`) applies as usual. The origin vouch does not bypass the device gate.

2. **Origin gate** (`origins.<origin_hash>.reviews.write`) — checked only when `review_access = invite_only`. The author must hold a live vouch where `subject_hash = author_hash` and `kind` attenuates from `origins.<origin_hash>.reviews.write`. No vouch = ingest rejected.

The two gates live in different root segments of the resource forest (`device` vs `origins`) — they never intersect and are evaluated as separate chain walks. This applies regardless of how the review is submitted — the vouch is the gate, not the token.

### Review hash capture

When the bot observes (via Electric shape) a new review for `(origin_hash, author_hash)` matching a bound token, it updates the token's `review_hash`, signs the updated row, and ingests it. This connects the token to its review for future redirects. Any device running the bot can perform this capture.

### Garbage collection

The review bot GCs its own tokens using `owner_timestamp` (bot clock), not server time:

Device-side in the `ReviewBotWorker`:

**Soft delete (configurable, default 7 days after creation):**
- Bot reads `review_token_ttl_days` from `origin_settings` (default: 7)
- Bot scans tokens where `user_hash IS NULL AND deleted_flag = false AND owner_timestamp < bot_clock - ttl_days`
- Sets `deleted_flag = true`, `owner_timestamp = original_owner_timestamp + 1`, re-signs
- The `+1` bump is intentionally minimal: if another device bound the token concurrently (using its bot clock, far higher), the bind wins LWW
- Ingests via `/ingest`

**Hard delete (2 weeks after soft delete, server-side):**
- Server deletes rows where `deleted_flag = true AND owner_timestamp < now - 3_weeks`
- The bot does not hard-delete — this is server-side cleanup (space preservation)

Multiple devices may race to soft-delete the same token — idempotent (same nonce PK, LWW on `owner_timestamp`). Bound and reviewed tokens are never GC'd.

---

## Origin Admin UI: "Enable Review Invitations"

A step in the origin admin interface where the owner creates the origin's review bot and delegates write scope to it. Everything happens client-side (or on the Nerves device) — the server only receives PQ rows via `/ingest`.

1. Owner opens origin settings
2. Clicks "Enable review invitations"
3. Client creates the review bot identity:
   - Generate ML-DSA-87 `sign_skey` / `sign_pkey` keypair
   - Generate ML-KEM-1024 `crypt_skey` / `crypt_pkey` keypair
   - Create `user_cards` row for the bot, named `ReviewBot_<originName>` (self-signed by bot's `sign_skey`)
   - POST `/ingest` — bot's `user_cards` enters the PQ system
4. Client encrypts bot identity: `{secret_b64, encrypted_identity_b64} = EnigmaPq.kem_encrypt(sign_skey <> crypt_skey, origin_crypt_pkey, "buckitup/origin-bot/v1")`
5. Client creates `origin_bots` row with `secret_b64` + `encrypted_identity_b64`, signed by origin identity
6. POST `/ingest` — `origin_bots` row enters the PQ system, Electric-synced to all devices holding this origin
7. Client constructs vouch tokens:
   - Origin gate vouch:
     - `kind: origins.<origin_hash>.reviews.write`
     - `issuer_hash: origin_hash`
     - `subject_hash: review_bot_hash`
     - Signs with origin's `sign_skey` (held client-side)
   - Device gate vouch:
     - `kind: device.<sn>.storage.write.<review_shapes>`
     - `issuer_hash: owner_hash`
     - `subject_hash: review_bot_hash`
     - Signs with owner's `sign_skey` (held client-side)
8. POST `/ingest` — both vouch tokens enter the PQ system
9. Device decrypts `encrypted_identity_b64`, starts `ReviewBotWorker` — the bot is live

On other devices: Electric syncs `origin_bots` rows → device decapsulates `secret_b64` with origin's `crypt_skey`, derives wrap key, decrypts `encrypted_identity_b64` → starts a `ReviewBotWorker` for each bot. Multiple devices can run bots simultaneously — token creation uses random nonces so there are no conflicts. If a device hasn't synced the existing bot yet, it may create a new one — both will work, and the origin vouches each independently.

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

## Review Access Setting

The `review_access` setting lives in the [`origin_settings`](pq_origin_settings.proposed.md) key-value table. The server reads it via `OriginSetting.get_review_access(origin_hash)`, which defaults to `"open"` when no row exists.

The `review_token_ttl_days` setting (also in `origin_settings`) controls the soft-delete span for pending tokens, in days (default: 7). The bot reads this to decide when to GC pending tokens.

---

## Implementation Phases

### Phase 1 — Origin bot + token infrastructure

- [ ] `origin_bots` migration + Ecto schema + Electric shape
- [ ] `OriginBotSignHash` type, `ob_` prefix in Consts
- [ ] `ReviewWriteTokenSignHash` type, `rwt_` prefix in Consts
- [ ] `OriginOrderHash` type, `org_ord_` prefix in Consts
- [ ] Bot creation flow: keypair gen, `user_cards` row (`ReviewBot_<originName>`), identity encryption, `origin_bots` ingest
- [ ] Bot vouch: origin → bot vouch token (`origins.<origin_hash>.reviews.write`)
- [ ] `ReviewBotWorker` GenServer: decrypt identity from `origin_bots` shape, start on sync
- [ ] `origin_settings` table + migration + Ecto schema + Electric shape
- [ ] `OriginSetting` data context, validation, shape module
- [ ] Review ingest: vouch check when `review_access = invite_only` (reads from `origin_settings`)

### Phase 2 — Token CRUD + redirect

- [ ] `review_write_tokens` migration (with nullable `origin_order_hash`, `parent_nonce`, integrity triad, `deleted_flag`) + Electric shape
- [ ] `ReviewWriteToken` Ecto schema
- [ ] `POST /r/api/token/create` — bot creates token (with or without order), returns nonce + URL
- [ ] `POST /r/api/token/bind` — bind user with PoP, bot issues per-shape vouches, redirect to frontend
- [ ] `/r/:nonce` Phoenix route — token state check + redirect to frontend
- [ ] Bot-side GC: soft delete pending tokens at 1 week
- [ ] Server-side GC: hard delete soft-deleted tokens after 2 weeks (3 weeks from creation)
- [ ] Origin admin: "enable invitations" UI (triggers Phase 1 bot creation + vouch)

### Phase 3 — QR

- [ ] QR code generation (frontend, from full URL)
- [ ] Printable QR sheet (multiple tokens per page)

---

## Open Questions

1. ~~**Review bot storage.**~~ — resolved. Bot identity stored in `origin_bots` table, encrypted to origin's `crypt_pkey`, Electric-synced across devices. See [Origin bot storage](#origin-bot-storage--origin_bots-table).

2. ~~**Token metadata for QR.**~~ — resolved. Token metadata lives on the order (`origin_order_hash`). The orders table design is deferred, but the link from token to order is established.

3. ~~**Orders table.**~~ — resolved. `origin_order_hash` is nullable. Tokens without an order are reusable invitation links (see Q11). The orders table design is deferred — when present, the hash is an opaque client-generated identifier with no FK constraint.

4. ~~**`/api/` endpoints vs existing ingest architecture.**~~ — resolved. Two REST endpoints under `/r/api/token/`:
   - `POST /r/api/token/create` — order/token creation (bot creates token, returns nonce + URL)
   - `POST /r/api/token/bind` — bind user to token (bot issues vouches, updates token)

   Token listing and deletion flow through Electric shapes + ingest (no REST). The `/r` scope sits before the catch-all in the router.

5. ~~**Hard delete mechanism.**~~ — resolved. The bot soft-deletes tokens (`deleted_flag = true`) at 1 week. The server hard-deletes soft-deleted rows after 2 more weeks (3 weeks from creation). No `:delete` through `/ingest` — hard delete is server-side only.

6. **Bot PoP (Proof of Possession) for ingest.** Every ingest requires `GET /electric/v1/challenge` → sign challenge with `sign_skey` → include `auth: {challenge_id, signature}` in the ingest body (see `IngestPop`). The spec should state that the bot fetches a challenge, signs it with `bot_sign_skey`, and includes it in each ingest call. The shape's `check` function verifies the bot's PoP against its `user_cards` `sign_pkey`.

7. ~~**`<review_shapes>` scope enumeration.**~~ — resolved. Per-shape vouches (narrow, explicit). The bot creates individual vouches for each shape the reviewer needs: `review`, `review_password_candidate`, `review_post_right_candidate`, `review_revoke_right_candidate`. No broad `storage.write` delegation.

8. ~~**Multi-device scope for device gate vouch.**~~ — resolved. The bot gets device scope for the device it runs on. If the origin owner wants multi-device support, they explicitly allow the bot on other devices as well (separate device-scoped vouches per device). No wildcards.

9. ~~**Encrypted identity format.**~~ — resolved. Two-field KEM wrap via `EnigmaPq.kem_encrypt/3` / `kem_decrypt/4`. Salt: `"buckitup/origin-bot/v1"`. See `Chat.Data.Schemas.OriginBot`.

10. ~~**`/r/:nonce` route placement.**~~ — resolved. The `/r` scope (containing `/:nonce`, `api/token/create`, `api/token/bind`) is placed before the catch-all `/*path` route. `FrontendController` gets a new `:write_review` action.

11. ~~**Concurrent bind race — dangling vouches.**~~ — resolved. Two token modes based on `origin_order_hash`:

    **Order-linked** (`origin_order_hash` set): one-time token. Concurrent binds resolve via LWW — the higher `owner_timestamp` wins. Dangling vouches from the loser are harmless (reviewer can't navigate to the review form without a bound token, and the vouch attenuates to a nonce that leads nowhere).

    **Reusable** (`origin_order_hash` null): multi-use invitation link. Binding does NOT modify the original token row — instead the bot creates a new bound token row (with a fresh nonce). The original pending token stays alive for more binds until soft-deleted.

    Soft-delete span is configurable per origin via `origin_settings` key `review_token_ttl_days` (default: 7).

12. ~~**Bot runtime location.**~~ — resolved. The bot runs on the device. The origin stores the bot's secret keys in `origin_bots` — `secret_b64` (KEM ciphertext) + `encrypted_identity_b64` (AES-GCM blob), decryptable only with the origin's `crypt_skey`. On device startup, the origin decapsulates, derives the wrap key, and decrypts the bot identity to start `ReviewBotWorker`. The bot keeps keys in memory while running. The server never sees secret keys in cleartext.

---

## Status

Proposed.

## References

- [pq_vouch_tokens](../pq_vouch_tokens.in_progress.md) — vouch token system, resource forest, attenuation
- [pq_reviews](pq_reviews.in_progress.md) — review system overview, pipeline, sandboxes
- [pq_review_moderation](pq_review_moderation.done.md) — moderation pipeline, candidate promotion
- [pq_origin](pq_origin.done.md) — origin entity, creation, ownership
- [pq_origin_settings](pq_origin_settings.proposed.md) — per-origin key-value settings (`review_access`)
- [pq_review_versioning](pq_review_versioning.done.md) — review editing, version chain

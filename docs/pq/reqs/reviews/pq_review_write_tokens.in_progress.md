# PQ Review Write Tokens

Links that lead a user to writing a review for a given origin.

## Goal

The origin identity generates a short URL (printable as QR, shareable via NFC/text/email) that, when opened, guides the visitor through identity creation (or import) and into writing a review for that specific origin. Tokens come in two modes: **order-linked** (one-time — once bound to a reviewer, it becomes a permanent redirect to that reviewer's review) and **reusable** (a standing invitation link that can bind many reviewers, each getting their own bound token copy).

---

## Token Lifecycle

A write token progresses through these states:

| State | `user_hash` | `review_hash` | `deleted_flag` | `parent_nonce_hash` | Behavior on visit |
|-------|-------------|---------------|----------------|----------------|-------------------|
| **pending** | null | null | false | null | Identity gate → bind → review form |
| **bound** | set | null | false | null or set | Review form (same user) / 403 (different user) |
| **reviewed** | set | set | false | null or set | Redirect to review (view/edit) |
| **soft-deleted** | null | null | true | null | "This link has expired" |

`parent_nonce_hash` is null on order-linked tokens and on the reusable parent. It is set on bound copies created from a reusable parent.

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
   │                │                    parent_nonce_hash = H(this nonce))      │
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

Each origin gets its own **review bot** — a PQ entity with its own `user_cards` row and full identity (ML-DSA-87 + ML-KEM-1024 keypairs). The review bot is created alongside the origin (or when the origin identity enables review invitations). Its `sign_pkey` is public via `user_cards`, so anyone can verify its vouch tokens.

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

**Bot startup flow (explicit, from admin page):**
1. Origin identity opens admin page, which lists `origin_bots` via Electric shape
2. Origin identity clicks "Start" on a bot row
3. Client decrypts: `identity = EnigmaPq.kem_decrypt(secret_b64, encrypted_identity_b64, origin_crypt_skey, "buckitup/origin-bot/v1")`
4. Client starts `ReviewBotWorker` GenServer under `Chat.ReviewBot.WorkerSupervisor` (DynamicSupervisor), registered via `Chat.ReviewBot.Registry`
5. Bot can now create tokens, issue vouches, GC — all on the device

The bot runs **on the origin identity's device** (or Nerves hardware), not on the server. Startup is explicit — the origin identity must decrypt and start each bot from the admin UI. Token creation and vouch issuance happen device-side, hitting `/ingest` the same way all other PQ rows do.

### Vouch chain

The origin identity vouches the review bot in both trees — origin scope for review authorization, device scope for write access to the shapes the reviewer will need:

```
Origin identity (also device owner)
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

**Origin → review bot (vouch 1):** The origin identity signs this vouch from their client using the origin's `sign_skey`. This is a deliberate step in the origin admin UI — the origin identity explicitly enables review invitations for their origin, which creates the review bot (if it doesn't exist) and vouches it.

**Device owner → review bot (vouch 2):** The device owner delegates write access to the specific shapes the reviewer needs (reviews, review candidates, etc.). Without this vouch, the reviewer's data would be rejected by the device gate even with a valid origin vouch. The device owner signs this with their own `sign_skey` — the device tree is rooted in the device owner, not the origin.

### Bot → reviewer delegation

On token bind, the review bot creates two vouch tokens — one per gate:

```
Vouch 1 (origin gate):
  kind:         origins.<origin_hash>.reviews.write.<nonce_hash>
  issuer_hash:  review_bot_hash
  subject_hash: reviewer_hash
  sign_b64:     signed with review bot's sign_skey

Vouch 2 (device gate):
  kind:         device.<sn>.storage.write.<review_shapes>
  issuer_hash:  review_bot_hash
  subject_hash: reviewer_hash
  sign_b64:     signed with review bot's sign_skey
```

Attenuation holds in both trees: `reviews.write.<nonce_hash>` is prefix-contained by `reviews.write`; `storage.write.<review_shapes>` is prefix-contained by the bot's own device write scope (see [Scope Attenuation](../pq_vouch_tokens.in_progress.md#scope-attenuation)). The bot cannot delegate wider than what it was granted.

The full verifiable chain: origin vouched review bot → review bot delegated to reviewer → reviewer wrote the review (ML-DSA-87 signed). Any peer can walk this chain using only public keys from `user_cards` and the vouch token rows.

The kind carries `nonce_hash`, never the nonce: vouch rows are public, and a plaintext nonce in a kind would hand anyone reading `vouch_tokens` a bindable link.

---

## URL Format

```
https://<host>/r/<nonce>
```

`<nonce>` is 24 random bytes, URL-safe base64 encoded (32 characters). Short enough for QR codes and NFC payloads. The full URL is the QR payload — no app-specific scanner required.

### Nonce secrecy

The nonce is a bearer secret: whoever holds it can bind the token. It is never stored or synced in plaintext. Everything persisted is keyed by

```
nonce_hash = "rwn_" <> hex(SHA3-512(nonce))     # EnigmaPq.hash/1, Types.ReviewWriteTokenNonceHash
```

The plaintext nonce exists only in:

- the `POST /r/api/token/create` and `POST /r/api/token/bind` responses
- the `/r/<nonce>` URL (QR / link)
- review ingest `auth.nonce`

Every entry point hashes the nonce first and works with `nonce_hash` from there on.

---

## Schema

### review_write_tokens

Electric-synced table with integrity triad. **Device-transparent** — any device running the origin's review bot can read and manage tokens. The durable trust proof is the vouch token in the PQ `vouch_tokens` table; this table handles token lifecycle and redirect logic.

Tokens are created by the review bot on the device when an order is opened. Every token is tied to an order — there are no unassigned tokens.

```
review_write_tokens
├── nonce_hash         — TEXT PK, prefix "rwn_" (SHA3-512 of the nonce)
├── nonce_enc_b64      — BYTEA NOT NULL (AES-256-GCM of the nonce, bot-only key)
├── origin_hash        — TEXT NOT NULL, FK → origins(origin_hash)
├── review_bot_hash    — TEXT NOT NULL, FK → user_cards(user_hash), prefix "u_" (signer — Signable lookup key)
├── origin_order_hash  — TEXT, nullable, prefix "org_ord_" (the order that triggered this token; null = reusable invitation)
├── parent_nonce_hash  — TEXT, nullable, prefix "rwn_" (set on bound copies of a reusable token; the parent's nonce_hash)
├── user_hash          — TEXT, nullable (null = pending; set = bound; set-once)
├── review_hash        — TEXT, nullable (set once review is written; set-once)
├── deleted_flag       — BOOLEAN NOT NULL DEFAULT false (soft-delete marker)
├── owner_timestamp    — BIGINT NOT NULL (bot clock, LWW)
├── sign_b64           — BYTEA NOT NULL (signed by review bot's sign_skey)
├── sign_hash          — TEXT NOT NULL, prefix "rwt_"
```

**`origin_order_hash`** — nullable. When set (prefix `org_ord_`), the token is order-linked and one-time. When null, the token is a reusable invitation link — binding creates a new bound token row instead of modifying this one. The orders table design is deferred — when present, the hash is an opaque client-generated identifier with no FK constraint.

**`owner_timestamp`** — bot monotonic clock, same convention as `owner_timestamp` elsewhere. The bot owns these rows and GCs against its own timeline.

**`review_bot_hash`** — identifies the signing bot. The `Signable` protocol uses this to look up the bot's `sign_pkey` from `user_cards` — same direct-lookup pattern as `author_hash` on reviews and `issuer_hash` on vouch tokens.

**`sign_b64` + `sign_hash`** — integrity triad. The review bot signs every token row (create, bind, review-hash capture, GC tombstone). Any device holding the bot identity can verify and update tokens.

**`nonce_hash`** — primary key, `rwn_` + SHA3-512 of the nonce (`Types.ReviewWriteTokenNonceHash.from_nonce/1`). Every lookup — `/r/<nonce>`, bind, review ingest — hashes the nonce and reads by this key, so none of them needs the bot. There are no plaintext `nonce` / `parent_nonce` columns.

**`nonce_enc_b64`** — the nonce, encrypted so the bot can re-display a link (QR, URL) after issue:

```
nonce_key     = EnigmaPq.hkdf_derive(bot crypt_skey, "buckitup/review-token-nonce/v1", "nonce")
nonce_enc_b64 = EnigmaPq.aes_gcm_encrypt(nonce, nonce_key)
```

Symmetric on purpose — the bot both writes and reads this column (`ReviewBot.Identity.wrap_nonce/2` / `unwrap_nonce/2`). This is not the two-field KEM wrap used by `origin_bots`: there the origin encrypts for a different party (the bot), here the same party encrypts and decrypts, so a KEM ciphertext would only add ~1.6 KB per row. Only a running bot (holding `crypt_skey`) can decrypt it.

**`parent_nonce_hash`** — nullable. Set on bound tokens created from a reusable (order-less) parent. Holds the parent's `nonce_hash`. Null on order-linked tokens and on the reusable parent itself.

**Set-once invariant** — `user_hash` and `review_hash` can only go from null to a value. Any update (bot via `/ingest` or peer sync) that changes or clears an already-set value is refused (`ReviewWriteToken.Validation.validate_set_once/2`). A bound token can never be rebound; a reviewed token can never be pointed at another review.

**No `max_uses`** — order-linked tokens are one-time: one nonce, one reviewer, one review. Reusable tokens (null `origin_order_hash`) can bind many reviewers — each bind produces a new token row with its own nonce and `parent_nonce_hash` pointing back to the reusable parent.

**No `expires_at`** — expiry is implicit: the bot GCs pending tokens older than its threshold. Bound tokens never expire.

**Electric shape** — devices filter by origins they hold keys for. Any device that starts its `ReviewBotWorker` sees all tokens for that origin and can create, bind, or GC them. Multiple devices creating tokens simultaneously is conflict-free (hashes of random nonces as PKs). Of the nonce, the shape carries only `nonce_hash` and `nonce_enc_b64` — nothing in it is bindable.

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

The server hashes the nonce and looks the token up by `nonce_hash` — no bot needed:

```
GET /r/:nonce                               (server: ReviewTokenController.show/2)
  ├── not found / soft-deleted   → 410 "This link has expired"
  └── otherwise                  → serve the SPA, which reads the token row
                                   (by nonce_hash) and its local identity:
      ├── bound to different user    → "This link was already used"
      ├── bound to current user,
      │   review_hash set            → redirect to that exact review (view/edit)
      ├── bound to current user,
      │   no review yet              → review form for this origin (carries the nonce)
      └── pending                    → login-kind landing page
                                       (identity create/import → PoP → /bind
                                        → review form)
```

**Who is "current user".** A `GET` from a scanned QR carries no identity — keys live in the SPA. So the server decides only "expired or not", and the per-user branches are decided client-side from the token's `user_hash` / `review_hash` (both public in the shape). This is display only: the security decisions are made server-side by bind (409 for another user) and by review ingest (exact bind vouch + token bound to the author).

The existing frontend handles identity creation, review writing, and the full review pipeline. No separate SPA flow needed.

### Token creation

`POST /r/api/token/create`:

1. Verify caller via AuthToken — a token encrypted by the origin for the bot (not PoP)
2. Bot generates nonce (24 random bytes, URL-safe base64)
3. Bot constructs token row — `nonce_hash = H(nonce)`, `nonce_enc_b64 = wrap_nonce(nonce)`, `origin_order_hash` optional (null = reusable invitation link) — and signs it
4. Bot ingests via `POST /ingest` — server validates bot signature + live vouch
5. Returns nonce + full URL (`https://<host>/r/<nonce>`) for QR generation — the only time the server hands out a new token's plaintext nonce

Re-displaying a link later (admin UI, printable QR) asks the running bot to unwrap `nonce_enc_b64`; the bot's `crypt_skey` never leaves the `ReviewBotWorker`.

Requires a live vouch: `kind = origins.<origin_hash>.reviews.write`, `issuer_hash = origin_hash`, `subject_hash = review_bot_hash`, `deleted_flag = false`. If no live vouch, rejects.

### Token bind

Binding is a multi-step browser flow, not a single API call:

1. **Landing** — visitor opens `/r/:nonce`, gets a login-kind page
2. **Identity** — visitor creates a new identity or imports an existing one
3. **Bind** — visitor proves PoP (signs challenge with `sign_skey`) to `POST /r/api/token/bind`
4. **Redirect** — on success, redirect to origin review (nonce) create/edit page

`POST /r/api/token/bind` (step 3) — needs the running bot:

1. **Rate limit** before anything else — per remote IP (`{:token_bind_ip, ip}`) and per claimed `user_hash` (`{:token_bind_user, user_hash}`), default 10/minute each. Over the limit → 429 with `retry-after`. Bounds nonce guessing and bind spam; checked before PoP so it is cheap to refuse.
2. Hash the nonce, look up the token by `nonce_hash`; not found or soft-deleted → reject
3. Verify the caller's identity: `user_cards` row exists with valid self-signature (PoP)
4. Verify the origin's review bot holds live vouches: `origins.<origin_hash>.reviews.write` (origin gate) and per-shape device gate vouches (`device.<sn>.storage.write.<shape>` for each of: `review`, `review_password_candidate`, `review_post_right_candidate`, `review_revoke_right_candidate`)
5. Apply the bind rules (below)
6. Review bot creates per-shape vouch tokens for the reviewer: `origins.<origin_hash>.reviews.write.<nonce_hash>` (origin gate, `nonce_hash` of the token the reviewer ends up bound to) and `device.<sn>.storage.write.<shape>` for each required shape (device gate)
7. **Order-linked token** (`origin_order_hash` set): bot updates the token row — sets `user_hash`, `owner_timestamp = bot_clock`, re-signs, ingests. Token is now one-time bound.
8. **Reusable token** (`origin_order_hash` null): bot creates a NEW token row with a fresh nonce — `nonce_hash = H(new_nonce)`, `nonce_enc_b64 = wrap_nonce(new_nonce)`, `parent_nonce_hash = original nonce_hash`, `user_hash = reviewer_hash`, `origin_order_hash = null` — signs and ingests. The original pending token stays untouched for more binds.
9. Respond with the nonce of the bound token (the new copy's nonce for a reusable parent) → redirect to the origin review create/edit page

**Bind rules:**

| Token | Caller | Result |
|-------|--------|--------|
| bound copy (`parent_nonce_hash` set) | anyone | 409 — a bound copy is not an invitation |
| order-linked, pending | — | bind |
| order-linked, bound to caller | caller | idempotent — return the same nonce, no new vouches needed |
| order-linked, bound to another user | caller | 409 — already used |
| reusable parent | caller already has a copy | idempotent — return that copy's nonce (unwrapped by the bot), no new copy |
| reusable parent | caller has no copy | mint a new copy |

So a reusable token gives at most one copy per `(root nonce_hash, user_hash)`. The set-once invariant on `user_hash` is the second line of defence: even a buggy bind cannot rebind a row.

### Review ingest validation

Review ingest passes through two independent gates — both must succeed:

1. **Device gate** (`device.<sn>.storage.write`) — the standard write gate. The review is a PQ row hitting `/ingest` on a device; the device's access mode (`guarded` / `trust`) applies as usual. The origin vouch does not bypass the device gate.

2. **Origin gate** (`origins.<origin_hash>.reviews.write`) — checked when `review_access = invite_only`:
   - **Direct vouch** — a live vouch with `subject_hash = author_hash` whose kind attenuates from `origins.<origin_hash>.reviews.write` but is *not* a token vouch (kind not ending in `.rwn_…`). Passes without a nonce.
   - **Token vouch** — if the author's only access is a token vouch, the review must carry `auth.nonce`; without it → rejected ("nonce required").

   The bot always provides vouches on bind regardless of mode, so reviewers retain access if the mode later switches to `invite_only`.

3. **Token check** — whenever the review carries `auth.nonce` (required as above in `invite_only`, optional in `open`), the server computes `nonce_hash = H(nonce)` and requires all of:
   - the token exists, is not soft-deleted, `origin_hash` matches the review
   - `user_hash = author_hash` (token bound to the author)
   - the token is unused (`review_hash` null) — or already linked to this same review (edit / new version)
   - the **exact** live vouch `origins.<origin_hash>.reviews.write.<nonce_hash>` with `subject_hash = author_hash` and `issuer_hash = token.review_bot_hash` — an exact-kind lookup, not a prefix match

   On success the review's `review_hash` is linked to that token (see [Review hash capture](#review-hash-capture)). The nonce selects which vouch is the gate; the exact bind vouch is the gate. One review per token: a reviewer may hold several tokens for the same origin (several orders), and each review links to the token whose nonce it carried. More reviews need another token or a direct vouch.

The device and origin gates live in different root segments of the resource forest (`device` vs `origins`) — they never intersect and are evaluated as separate chain walks. Review ingest needs no bot: everything it checks is keyed by `nonce_hash` and public vouch rows.

### Review hash capture

~~When the bot observes (via Electric shape) a new review for `(origin_hash, author_hash)` matching a bound token, it updates the token's `review_hash`, signs the updated row, and ingests it.~~

**Implemented:** review hash linking happens atomically at ingest time. When a reviewer submits a review with `auth.nonce`, the server hashes it and `ReviewWriteToken.link_to_review/3` sets `review_hash` on the token row found by `nonce_hash`, inside the same transaction as the review insert. `review_hash` is set-once — a token cannot be re-pointed at another review. The review gate (`Validation.check_review_gate/2`) runs in the `check` phase — before validation — alongside the device gate. This eliminates the async observe-and-backfill pattern as the primary mechanism.

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

Multiple devices may race to soft-delete the same token — idempotent (same `nonce_hash` PK, LWW on `owner_timestamp`). Bound and reviewed tokens are never GC'd. The tombstone keeps `nonce_hash` and `nonce_enc_b64`; neither is bindable.

---

## Bot Dependency

| Operation | Needs running bot | Why |
|-----------|-------------------|-----|
| `GET /r/<nonce>` | no | lookup by `nonce_hash` |
| Review ingest (gate + link) | no | `nonce_hash` + public vouch rows |
| Token create | yes | bot signs the row, encrypts the nonce |
| Token bind | yes | bot issues vouches, signs the row, unwraps an existing copy's nonce |
| GC (soft delete) | yes | bot re-signs the tombstone |
| Re-displaying a link / QR | yes | only the bot can unwrap `nonce_enc_b64` |

---

## Security

The nonce is the only bearer secret in this design. Nothing readable by a third party lets anyone bind:

- **`/shapes` (`review_write_tokens`)** — carries `nonce_hash` and `nonce_enc_b64` only. The hash is one-way (SHA3-512 of 24 random bytes); the ciphertext needs the bot's `crypt_skey`.
- **`vouch_tokens`** — kinds end in `<nonce_hash>`, not the nonce.
- **Peer sync** — syncs the same rows; the set-once invariant stops a peer from rebinding (`user_hash`) or re-pointing (`review_hash`) a token.
- **Holding a vouch without the nonce** — not enough in `invite_only` when the vouch is a token vouch: ingest requires `auth.nonce` and the token bound to the author.
- **Guessing** — 192-bit nonces; bind is rate-limited per IP and per `user_hash`.

The plaintext nonce reaches only the origin backend (create response), the reviewer (link / QR, bind response) and the server for the duration of a request.

---

## Origin Admin UI: "Enable Review Invitations"

A step in the origin admin interface where the origin identity creates the review bot and delegates write scope to it. Everything happens client-side (or on the Nerves device) — the server only receives PQ rows via `/ingest`.

1. Origin identity opens origin settings
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

Revoking: the origin identity can revoke the review bot's vouch (signed tombstone, `deleted_flag: true`). Existing bound tokens remain valid (the vouch for the individual reviewer is already issued), but no new tokens can be created.

---

## Relationship to Existing Systems

### Review pipeline — unchanged

The vouch token gates entry (when `review_access = invite_only`). Once the reviewer has identity + vouch, they use the standard pipeline via the existing frontend: review → candidate → promotion → rights. The origin's `moderation_mode` applies as usual. The write token is the delivery mechanism for the vouch — the vouch itself is the permission.

### Vouch tokens — consumer

Write tokens consume the vouch token infrastructure for trust delegation. The `origins.<origin_hash>.reviews.write.<nonce_hash>` scope sits in the origins subtree of the [Resource Forest](../pq_vouch_tokens.in_progress.md#resource-forest).

### Review access mode — per-origin policy

The origin identity decides whether reviews are open or invitation-only. A new field on the `origins` table:

| `review_access` | Behavior |
|-----------------|----------|
| `open` (default) | Anyone with an identity can write a review. Bot still provides vouches on bind (provenance + future-proofing). |
| `invite_only` | Review ingest requires a vouch in `origins.<origin_hash>.reviews.write.*` scope. No vouch = rejected. |

**Enforcement at ingest.** When `review_access = invite_only`, `Review.Validation` checks for a live (non-tombstoned) vouch token where `subject_hash = author_hash` and `kind` attenuates from `origins.<origin_hash>.reviews.write`. Direct vouches pass on their own; bot-delegated token vouches (`reviews.write.<nonce_hash>`) pass only together with `auth.nonce` and the token check (see [Review ingest validation](#review-ingest-validation)). In `open` mode the origin gate is not checked, but a supplied nonce is still validated.

**Vouches always provided.** The bot issues vouch tokens on every bind, regardless of `review_access` mode. This ensures that reviewers who obtained access in `open` mode retain it if the origin later switches to `invite_only`.

**Mode change with existing reviews.** Switching from `open` to `invite_only` does not retroactively affect existing reviews — they are already in the pipeline. Reviewers who bound tokens in `open` mode already hold vouches, so new submissions are still accepted. Switching from `invite_only` to `open` is immediate.

**Relationship to moderation.** `review_access` controls who can *enter* the pipeline. `moderation_mode` controls what happens *inside* the pipeline. They are orthogonal — an `invite_only` origin can still run `pre` moderation on invited reviews.

---

## Review Access Setting

The `review_access` setting lives in the [`origin_settings`](pq_origin_settings.done.md) key-value table. The server reads it via `OriginSetting.get_review_access(origin_hash)`, which defaults to `"open"` when no row exists.

The `review_token_ttl_days` setting (also in `origin_settings`) controls the soft-delete span for pending tokens, in days (default: 7). The bot reads this to decide when to GC pending tokens.

---

## Implementation Phases

### Phase 1 — Origin bot + token infrastructure

- [x] `origin_bots` migration + Ecto schema + Electric shape
- [x] `OriginBotSignHash` type, `ob_` prefix in Consts
- [x] `ReviewWriteTokenSignHash` type, `rwt_` prefix in Consts
- [x] `OriginOrderHash` type, `org_ord_` prefix in Consts
- [x] Bot creation flow: keypair gen, `user_cards` row (`ReviewBot_<originName>`), identity encryption, `origin_bots` ingest
- [x] Bot vouch: origin → bot vouch token (`origins.<origin_hash>.reviews.write`)
- [x] `ReviewBotWorker` GenServer: decrypt identity from `origin_bots`, explicit start from admin page
- [x] `origin_settings` table + migration + Ecto schema + Electric shape
- [x] `OriginSetting` data context, validation, shape module
- [x] Review ingest: origin gate vouch check when `review_access = invite_only` (reads from `origin_settings`)

### Phase 2 — Token CRUD + redirect

- [x] `review_write_tokens` migration (with nullable `origin_order_hash`, `parent_nonce`, integrity triad, `deleted_flag`) + Electric shape
- [x] `ReviewWriteToken` Ecto schema
- [x] `POST /r/api/token/create` — bot creates token (with or without order), returns nonce + URL
- [x] `POST /r/api/token/bind` — bind user with PoP, bot issues per-shape vouches, redirect to frontend
- [x] `/r/:nonce` Phoenix route — token state check + redirect to frontend
- [x] Bot-side GC: soft delete pending tokens at 1 week (`GarbageCollector` + `GcServer`)
- [x] Server-side GC: hard delete soft-deleted tokens after 2 weeks (`GcServer.hard_delete_old_tombstones`)
- [x] Origin admin: sandbox-level UI for bot creation, token creation, settings, and bind flow

### Phase 2a — Review hash capture (spec amendment)

- [x] Review gate moved from `validate` to `check` phase (`Validation.check_review_gate/2` chained in `Shapes.Review`)
- [x] Nonce-based `review_hash` linking at ingest time (`ReviewWriteToken.link_to_review/3`) — atomic, replaces the async bot-observes-and-backfills pattern described in the original spec

### Phase 3 — QR

- [x] QR code generation (reuses existing `Utils.qr_base64_from_url`, sandbox references QR nonce URLs)
- [ ] Printable QR sheet (multiple tokens per page)

### Phase 4 — Nonce secrecy and bind rules (#831 follow-up)

- [ ] Spec amendment — this document (#833)
- [ ] `nonce_hash` PK + `nonce_enc_b64`, no plaintext nonce columns (#836)
- [ ] Set-once `user_hash` / `review_hash` on every update path (#834)
- [ ] Rate limit `POST /r/api/token/bind` (#835)
- [ ] Review ingest: exact bind vouch by `nonce_hash`, nonce required for token vouches (#838)
- [ ] `TokenBinder` bind rules: no bound copies, no rebinding, one copy per (root, user) (#839)
- [ ] Sandboxes show own links via bot unwrap; end-to-end test with no plaintext nonce stored (#841)

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

8. ~~**Multi-device scope for device gate vouch.**~~ — resolved. The bot gets device scope for the device it runs on. If the origin identity wants multi-device support, they explicitly allow the bot on other devices as well (separate device-scoped vouches per device). No wildcards.

9. ~~**Encrypted identity format.**~~ — resolved. Two-field KEM wrap via `EnigmaPq.kem_encrypt/3` / `kem_decrypt/4`. Salt: `"buckitup/origin-bot/v1"`. See `Chat.Data.Schemas.OriginBot`.

10. ~~**`/r/:nonce` route placement.**~~ — resolved. The `/r` scope (containing `/:nonce`, `api/token/create`, `api/token/bind`) is placed before the catch-all `/*path` route. `FrontendController` gets a new `:write_review` action.

11. ~~**Concurrent bind race — dangling vouches.**~~ — resolved. Two token modes based on `origin_order_hash`:

    **Order-linked** (`origin_order_hash` set): one-time token. Concurrent binds resolve via LWW — the higher `owner_timestamp` wins. Dangling vouches from the loser are harmless: review ingest requires the token to be bound to the author, so a vouch for a token bound to someone else opens nothing.

    **Reusable** (`origin_order_hash` null): multi-use invitation link. Binding does NOT modify the original token row — instead the bot creates a new bound token row (with a fresh nonce). The original pending token stays alive for more binds until soft-deleted.

    Soft-delete span is configurable per origin via `origin_settings` key `review_token_ttl_days` (default: 7).

12. ~~**Bot runtime location.**~~ — resolved. The bot runs on the device. The origin stores the bot's secret keys in `origin_bots` — `secret_b64` (KEM ciphertext) + `encrypted_identity_b64` (AES-GCM blob), decryptable only with the origin's `crypt_skey`. On device startup, the origin decapsulates, derives the wrap key, and decrypts the bot identity to start `ReviewBotWorker`. The bot keeps keys in memory while running. The server never sees secret keys in cleartext.

13. ~~**Where the nonce lives.**~~ — resolved. Key rows by `nonce_hash = H(nonce)` and keep the nonce encrypted for the bot in `nonce_enc_b64` (see [Nonce secrecy](#nonce-secrecy)). Rejected alternatives:
    - **Plain hash only** — rejected: links are not recoverable after issue. If the create response never reaches a client (crash, restart), the token is lost; the admin UI cannot re-show a QR.
    - **Encryption only, with a bot-side nonce index** — rejected: `/r/` and review ingest would depend on a running bot, and the index must be kept in sync across devices and peer sync.
    - **Per-token KEM wrap** (like `origin_bots`) — rejected: the same party encrypts and decrypts, so KEM adds nothing but ~1.6 KB of ciphertext per row.

14. ~~**Token gate vs vouch gate.**~~ — resolved. Earlier text said "the vouch is the gate, not the token". Refined: the exact bind vouch `reviews.write.<nonce_hash>` is the gate, and the nonce selects it. A prefix match over the author's vouches is not enough — it would let one token's vouch cover any review.

15. ~~**`/r/:nonce` and the current user.**~~ — resolved. The server answers only "expired / not found"; the per-user branches are decided by the SPA from public token state. Enforcement is at bind and ingest (see [Route](#route)).

---

## Status

In progress. Phase 1, 2, 2a complete. Phase 3 partial (QR generation done, printable sheet pending). Phase 4 (nonce secrecy) in progress.

## References

- [pq_vouch_tokens](../pq_vouch_tokens.in_progress.md) — vouch token system, resource forest, attenuation
- [pq_reviews](pq_reviews.in_progress.md) — review system overview, pipeline, sandboxes
- [pq_review_moderation](pq_review_moderation.done.md) — moderation pipeline, candidate promotion
- [pq_origin](pq_origin.done.md) — origin entity, creation, ownership
- [pq_origin_settings](pq_origin_settings.done.md) — per-origin key-value settings (`review_access`)
- [pq_review_versioning](pq_review_versioning.done.md) — review editing, version chain

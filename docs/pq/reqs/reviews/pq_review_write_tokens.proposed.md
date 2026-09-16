# PQ Review Write Tokens

One-time links that lead a user to writing a review for a given origin.

## Goal

An origin owner generates a short URL (printable as QR, shareable via NFC/text/email) that, when opened, guides the visitor through identity creation (or import) and into writing a review for that specific origin. The token is one-time — once bound to a reviewer, it becomes a permanent redirect to that reviewer's review.

---

## Token Lifecycle

A write token progresses through three states:

| State | `user_hash` | `review_hash` | Behavior on visit |
|-------|-------------|---------------|-------------------|
| **pending** | null | null | Identity gate → bind → review form |
| **bound** | set | null | Review form (same user) / 403 (different user) |
| **reviewed** | set | set | Redirect to review (view/edit) |

```
pending  ──visit──▶  identity gate  ──PoP──▶  bound  ──submit──▶  reviewed
                         │                                            │
                    create / import                              permanent link
                      identity                                  to author's review
```

Tokens that remain **pending** for longer than 1 month are garbage-collected. Bound and reviewed tokens persist indefinitely — they are permanent links.

---

## Trust Delegation

Write tokens are authorized through a two-level vouch chain rooted in the [vouch tokens](../pq_vouch_tokens.proposed.md) system.

### Bot identity

The bot is a server-side PQ entity with its own `user_cards` row. It holds its own `sign_skey` (storage location is out of scope — a bots table with secret keys, managed separately). The bot's `sign_pkey` is public via `user_cards`, so anyone can verify its vouch tokens.

One bot per server serves all origins. Cross-origin leakage is prevented by scope attenuation — a vouch for `origins.<A>.reviews.write` does not cover `origins.<B>.reviews.write`.

### Vouch chain

Two vouches must exist before the bot can issue write tokens for an origin:

```
Admin (device owner)
  │
  │  Approval-list or broad vouch — "this bot is a trusted system entity"
  │  (one-time system setup)
  ▼
Bot (server-side, sign_skey in bots table)
  ▲
  │  Vouch token:
  │    kind:         origins.<origin_hash>.reviews.write
  │    issuer_hash:  origin_hash
  │    subject_hash: bot_hash
  │    sign_b64:     signed with origin's sign_skey (client-side)
  │
Origin owner (per-origin, via origin admin UI: "enable review invitations")
```

**Admin → bot:** System-level trust. The admin vouches for the bot entity, or adds it to the approval list. Done once during system setup.

**Origin → bot:** Per-origin delegation. The origin owner signs this vouch from their client using the origin's `sign_skey`. This is a deliberate step in the origin admin UI — the owner explicitly enables review invitations for their origin.

### Bot → reviewer delegation

On token bind, the bot creates a vouch token:

```
kind:         origins.<origin_hash>.reviews.write.<nonce>
issuer_hash:  bot_hash
subject_hash: reviewer_hash
sign_b64:     signed with bot's sign_skey
```

Attenuation holds: `reviews.write.<nonce>` is prefix-contained by `reviews.write` (see [Scope Attenuation](../pq_vouch_tokens.proposed.md#scope-attenuation)).

The full verifiable chain: origin trusted bot → bot delegated to reviewer → reviewer wrote the review (ML-DSA-87 signed). Any peer can walk this chain using only public keys from `user_cards` and the vouch token rows.

---

## URL Format

```
https://<host>/r/<nonce>
```

`<nonce>` is 24 random bytes, URL-safe base64 encoded (32 characters). Short enough for QR codes and NFC payloads. The full URL is the QR payload — no app-specific scanner required.

---

## Schema

### review_write_tokens

Server-side operational table. **Not Electric-synced, no integrity triad.** The durable proof is the vouch token in the PQ `vouch_tokens` table; this table is the redirect logic.

```
review_write_tokens
├── nonce              — TEXT PK (URL-safe base64, 32 chars)
├── origin_hash        — TEXT NOT NULL, FK → origins(origin_hash)
├── user_hash          — TEXT, nullable (null = pending; set = bound)
├── review_hash        — TEXT, nullable (set once review is written)
├── vouch_sign_hash    — TEXT, nullable (sign_hash of the vouch token created on bind)
├── created_at         — TIMESTAMPTZ NOT NULL, DEFAULT now()
├── bound_at           — TIMESTAMPTZ, nullable
```

**No `sign_b64`** — this is server-managed state. The vouch token (in `vouch_tokens`, PQ-signed by the bot) is the cryptographic proof.

**No `max_uses`** — tokens are one-time. One nonce, one reviewer, one review.

**No `expires_at`** — expiry is implicit: the GC job deletes pending tokens older than 1 month. Bound tokens never expire.

Indexes: `origin_hash` (list tokens per origin), `user_hash` (lookup by reviewer).

---

## Frontend

### Route

```
/r/:nonce → FrontendController, :write_review
```

Phoenix serves the SPA with the token's nonce in context. The SPA handles everything from there.

### SPA route

```
/#/review/write/:nonce
```

### Mount flow

```
GET /api/write_tokens/:nonce
  ├── not found / GC'd           → "This link has expired"
  ├── bound to different user     → "This link was already used"
  ├── bound to current user,
  │   review exists               → redirect to review (view/edit)
  ├── bound to current user,
  │   no review yet               → show review form
  └── pending                     → show identity gate
```

### Identity gate

Shown when the token is pending and the visitor has no identity (or needs to present one).

```
┌────────────────────────────────────────┐
│  Write a review for: ☕ Origin Name    │
│                                        │
│  ○ Create new identity                 │
│    [generating keys... ⏳]             │
│                                        │
│  ○ Import existing identity            │
│    [paste / file / scan]               │
└────────────────────────────────────────┘
```

**Keygen starts immediately on mount** in a Web Worker — ML-DSA-87 + ML-KEM-1024 keypair generation runs in the background while the user reads the origin info. By the time they choose "create new," keys are likely ready. If the user picks "import," the pre-generated keys are discarded.

On identity ready (created or imported):

1. Self-sign `user_cards` row (this is the PoP)
2. POST `/ingest` — `user_cards` row
3. Present identity to token bind endpoint
4. Bot verifies PoP (user_cards exists, self-signed, valid)
5. Bot creates vouch token (see [Bot → reviewer delegation](#bot--reviewer-delegation))
6. Token record updated: `user_hash` set, `bound_at` set
7. Transition to review form

### Review form

Once bound, the standard review writing flow:

```
┌────────────────────────────────────────┐
│  Review for: ☕ Origin Name            │
│                                        │
│  Rating:  ★ ★ ★ ★ ☆                   │
│                                        │
│  Your review:                          │
│  ┌──────────────────────────────────┐  │
│  │                                  │  │
│  └──────────────────────────────────┘  │
│                                        │
│  [Submit]                              │
└────────────────────────────────────────┘
```

On submit, the frontend drives the existing review pipeline:

1. Generate `review_password` (random 32 bytes)
2. Compose content model: `[rating, placeholder, content]`
3. Encrypt with `review_password` (AES-256-GCM) → `content_b64`
4. Sign `content_b64` with author's ML-DSA-87 → `sign_b64`
5. POST review to `/ingest`
6. POST password candidate + null candidate to `/ingest`
7. Wait for promotion (poll or Electric shape)
8. If post/pre mode: sign right candidates when they appear
9. Pipeline complete → token record updated with `review_hash`
10. Show confirmation / redirect to review view

The pipeline orchestration follows the same steps as [ReviewSandboxLive](../../../../lib/chat_web/live/electric_live/review_sandbox_live/index.ex), adapted for the SPA.

### Return visit

If the same user opens `/r/<nonce>` again:

- **Review exists** → redirect to the review view/edit page
- **No review yet** (abandoned form) → show review form again

Editing follows the existing [review versioning](pq_review_versioning.done.md) rules — same `review_hash`, new `content_b64` + `sign_b64`, parent chain linking.

---

## Backend

### API endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /api/origins/:origin_hash/write_tokens` | Origin owner | Create token(s), returns URL(s) |
| `POST /api/origins/:origin_hash/write_tokens/batch` | Origin owner | Create multiple tokens at once (for QR printing) |
| `GET /api/write_tokens/:nonce` | Public | Validate token → returns origin info + token state |
| `POST /api/write_tokens/:nonce/bind` | Authenticated (PoP) | Bind token to user, bot issues vouch |
| `GET /api/origins/:origin_hash/write_tokens` | Origin owner | List active tokens for this origin |
| `DELETE /api/origins/:origin_hash/write_tokens/:nonce` | Origin owner | Revoke (delete) a token |

### Token creation

Requires:
1. Caller is the origin's `owner_hash`
2. A vouch token exists: `kind = origins.<origin_hash>.reviews.write`, `issuer_hash = origin_hash`, `subject_hash = bot_hash`, `deleted_flag = false`

If the origin→bot vouch doesn't exist, return an error directing the owner to enable review invitations first.

### Token bind

The `/bind` endpoint:

1. Validate the token is pending
2. Verify the caller's identity: `user_cards` row exists with valid self-signature
3. Verify the bot holds the `reviews.write` scope for this origin (vouch chain check)
4. Bot creates vouch token `origins.<origin_hash>.reviews.write.<nonce>` for the reviewer
5. Update token record: `user_hash`, `vouch_sign_hash`, `bound_at`
6. Return success + origin info for the review form

### Review hash capture

When a review is ingested for `(origin_hash, author_hash)` matching a bound token, the ingest post-apply hook updates the token's `review_hash`. This connects the token to its review for future redirects.

### Garbage collection

`ReviewWriteTokenCleaner` — periodic job, same pattern as [`ReviewCandidateCleaner`](../../../../lib/chat/data/review_candidate_cleaner.ex):

- Runs every hour (or daily — low urgency)
- Deletes tokens where `user_hash IS NULL AND created_at < now() - interval '1 month'`
- Bound tokens without reviews (abandoned) could get a longer TTL (3 months) or be kept indefinitely

---

## Origin Admin UI: "Enable Review Invitations"

A step in the origin admin interface where the owner delegates write scope to the bot:

1. Owner opens origin settings
2. Clicks "Enable review invitations"
3. Client constructs vouch token:
   - `kind: origins.<origin_hash>.reviews.write`
   - `issuer_hash: origin_hash`
   - `subject_hash: bot_hash` (well-known, published in server config or discoverable via API)
   - Signs with origin's `sign_skey` (held client-side)
4. POST `/ingest` — vouch token enters the PQ system via normal Electric sync
5. The "Generate invite link" button becomes available

Revoking: the owner can revoke the bot's vouch (signed tombstone, `deleted_flag: true`). Existing bound tokens remain valid (the vouch for the individual reviewer is already issued), but no new tokens can be created.

---

## Relationship to Existing Systems

### Review pipeline — unchanged

The write token gates entry. Once the reviewer has identity + vouch, they use the standard pipeline: review → candidate → promotion → rights. The origin's `moderation_mode` applies as usual.

### Vouch tokens — consumer

Write tokens consume the vouch token infrastructure for trust delegation. The `origins.<origin_hash>.reviews.write.<nonce>` scope was designed for this use case (see [Scope Vocabulary](../pq_vouch_tokens.proposed.md#scope-vocabulary)).

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

### Phase 1 — Token CRUD + redirect

- [ ] `review_access` column on `origins` + migration
- [ ] `review_access` in Origin schema, validation, Signable
- [ ] Review ingest: vouch check when `review_access = invite_only`
- [ ] `review_write_tokens` migration
- [ ] `ReviewWriteToken` Ecto schema
- [ ] Token creation/validation/deletion controller
- [ ] `/r/:nonce` Phoenix route → SPA
- [ ] `ReviewWriteTokenCleaner` periodic job
- [ ] Origin admin: "enable invitations" vouch creation

### Phase 2 — SPA write flow

- [ ] `/#/review/write/:nonce` SPA route
- [ ] Token validation + origin info fetch on mount
- [ ] Identity gate: create new (Web Worker keygen) or import
- [ ] Token bind flow (PoP → bot vouch → redirect)
- [ ] Review form (rating + text, content model)
- [ ] Pipeline orchestration (adapted from review sandbox)
- [ ] Return-visit redirect (bound → review form or view/edit)

### Phase 3 — Batch + QR

- [ ] Batch token creation endpoint
- [ ] QR code generation (frontend, from full URL)
- [ ] Printable QR sheet (multiple tokens per page)

---

## Open Questions

1. **Bot identity bootstrap.** How is the bot's `user_cards` row created on first server start? Out of scope for this doc — depends on the bots table design.

2. **Multi-device identity.** A user opens the link on their phone but their identity is on desktop. The "import identity" option addresses this, but the UX of cross-device import (scan QR from desktop? paste export string?) needs design.

3. **Review without completing pipeline.** If the user submits a review but closes the tab before signing right candidates (post/pre mode), the pipeline stalls. The token is bound, the review exists, but promotion is incomplete. On return visit, the frontend should detect the stalled pipeline and resume it.

4. **Token metadata for QR.** Should the origin be able to attach a label or note to a token (e.g., "Table 7", "Event: Sep 2026") for their own tracking? Not shown to the reviewer.

---

## Status

Proposed.

## References

- [pq_vouch_tokens](../pq_vouch_tokens.proposed.md) — vouch token system, scope vocabulary, attenuation
- [pq_reviews](pq_reviews.in_progress.md) — review system overview, pipeline, sandboxes
- [pq_review_moderation](pq_review_moderation.done.md) — moderation pipeline, candidate promotion
- [pq_origin](pq_origin.done.md) — origin entity, creation, ownership
- [pq_review_versioning](pq_review_versioning.done.md) — review editing, version chain

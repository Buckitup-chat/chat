# PQ Reviews

## Goal

Add a review system for origin entities (businesses, venues, etc.) with post-quantum cryptographic guarantees matching the rest of the platform.

A user should be able to:

- discover origins (coffee shops, venues, etc.)
- write a review with chosen visibility: to_public or to_origin
- comment on any review they can see
- trust that visibility guarantees are cryptographic, not server-enforced

An origin owner should be able to:

- register an origin with its own PQ identity
- choose a moderation mode for public reviews (pre, post, or none)

The origin identity (not the owner) should be able to:

- moderate public reviews (approve, reject, hide) — delegatable without exposing owner identity
- receive private feedback (to_origin reviews)

## Design decisions

- **Rating**: incorporate into a content model `[rating, placeholder, content]` — fill placeholder with random string to make rating-only and text reviews indistinguishable in ciphertext size. See [Content model](pq_review_moderation.done.md#content-model).
- **`to_origin` is not a feature**: because the origin is a `user_cards` identity, a `to_origin` review is a plain dialog message to the origin's `user_hash`. No schema, no shape, no validation, no moderation path — nothing to build beyond a UI entry point. See [to_origin](pq_review_moderation.done.md#to_origin).
- **Passwords vs reviews**: passwords as access layer. Prevent deletion as much as possible.
- **Ingest via candidates**: all *author-submitted* `review_public_passwords` entries flow through `review_password_candidate` — the server validates and promotes. See [Candidate-only ingest](pq_review_moderation.done.md#candidate-only-ingest).
- **Origin key management**: origin keypairs are independently generated on the client (not derived from owner keys), stored client-side in the owner's identity, same pattern as regular user keys (see [pq_user.done.md](../pq_user.done.md)). Multi-device access via User Storage.
- **Origin creation**: three-step flow. See [Origin creation](pq_origin.done.md#origin-creation).

## Three entities

```
Origin (the coffee shop)
│  subaccount identity (user_cards row), owned by a user
│
└── Review (by any user)
    ├── to_public   — encrypted with review_password, signed by author
    │                 public when password in review_public_passwords table
    │                 contacts see via review_list_password (bypasses moderation)
    ├── to_origin  — plain dialog between author and origin identity (see pq_dialogs.done),
    │                 no review-specific machinery
    │
    └── Comment (by anyone who can see the parent review)
        └── inherits parent review's visibility envelope
```

## Sub-documents

| Doc | Status | Covers |
|-----|--------|--------|
| [Origin](pq_origin.done.md) | done | Origin entity, creation, ownership, schema, shape |
| [Moderation](pq_review_moderation.done.md) | done | Crypto pipeline, visibility tiers, content model, comments, schemas, shapes, security |
| [Contacts](pq_review_contacts.done.md) | done | Contacts channel, review_list, key delivery, proof matrix |
| [Versioning](pq_review_versioning.in_progress.md) | in_progress | Review editing, version chain, pre-mode lock, review_versions table |

## Sandboxes

Four sandboxes plus a public viewer, split by persona — each operates under a distinct identity context:

### Origin owner sandbox

[`OriginSandboxLive`](../../../../lib/chat_web/live/electric_live/origin_sandbox_live/index.ex): the user who creates and owns the origin. Exercises:

- generate origin ML-DSA-87 + ML-KEM-1024 keypairs (independent of owner keys)
- insert origin `user_cards` row (self-signed)
- create `origin` row with `owner_cert` (owner signs origin's `sign_pkey`)
- set/change moderation mode
- delete (soft delete via `deleted_flag`)
- export origin identity (for admin/moderator sandbox)

### Origin admin/moderator sandbox

[`ModerationSandboxLive`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/index.ex): authenticates as the origin identity (not the owner's personal identity). Modules: [`Identity`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/identity.ex), [`Queue`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/queue.ex), [`Entries`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/entries.ex), [`ApiClient`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/api_client.ex), [`Render`](../../../../lib/chat_web/live/electric_live/moderation_sandbox_live/render.ex). Exercises:

- import the origin identity export and prove it against the origin's `user_cards` row (signature + KEM round-trip)
- read the origin's reviews, password rows and right envelopes via Electric shapes
- pre-moderation: decrypt `review_post_right` (KEM decapsulate) — this is also how the moderator reads a review *before* approving it — then ingest the pre-signed password row
- post-moderation: decrypt `review_revoke_right` (KEM decapsulate), ingest the pre-signed null row
- moderation round-trip with the author sandbox

`to_origin` reviews are not exercised here — they are plain dialogs with the origin identity, covered by the existing dialog infrastructure and its own sandbox.

### Review visitor/author sandbox

[`ReviewSandboxLive`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/index.ex): a regular user browsing and writing reviews. Modules: [`ApiClient`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/api_client.ex), [`Http`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/http.ex), [`ReviewList`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/review_list.ex), [`ReviewList.Proofs`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/review_list/proofs.ex), [`Verification`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/verification.ex), [`Contacts`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/contacts.ex), [`ListPassword`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/list_password.ex), [`Render`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/render.ex), [`RenderReviewList`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/render_review_list.ex), [`RenderVerification`](../../../../lib/chat_web/live/electric_live/review_sandbox_live/render_verification.ex). Exercises:

- browse origins (public directory)
- view public reviews (decrypt with `review_password` from `review_public_passwords`)
- view contacts' reviews (decrypt via `review_list_password` from `review_list`)
- write `to_public` review: generate `review_password`, AES-256-GCM encrypt, ML-DSA-87 sign `content_b64`, submit password candidate
- write `to_origin` review: plain dialog message to the origin's `user_hash` — no review-specific path
- moderation pipeline participation: ingest candidates (server triggers promotion), read right candidates via Electric shape, verify KEM wrapping, ingest signature updates (server triggers completion)

### Public reviews viewer

[`OriginReviewsLive`](../../../../lib/chat_web/live/electric_live/origin_reviews_live/index.ex): no identity required — a read-only view simulating the public frontend. Exercises:

- browse origin directory (list all origins with moderation mode)
- select an origin to view its public reviews
- decrypt `content_b64` using `password_b64` from `review_public_passwords` (AES-256-GCM)
- render decoded content model: star rating (1–5), review text
- display reviews pending moderation or hidden by moderation as distinct states

### Contacts reader sandbox

[`ContactsReaderLive`](../../../../lib/chat_web/live/electric_live/contacts_reader_live/index.ex): a user reading their contacts' reviews. Imports an identity, then derives the contact set from dialogs rather than a persisted contact list. Modules: [`KeyScanner`](../../../../lib/chat_web/live/electric_live/contacts_reader_live/key_scanner.ex), [`ReviewReader`](../../../../lib/chat_web/live/electric_live/contacts_reader_live/review_reader.ex), [`Render`](../../../../lib/chat_web/live/electric_live/contacts_reader_live/render.ex). Exercises:

- import identity and verify against `user_cards`
- scan dialogs for `review_list_key` messages to discover contacts who shared their list password
- read own and contacts' `review_list` rows (trimmed `columns=`), decrypt `password_b64`
- fetch per-origin reviews for each discovered contact, decrypt content
- cross-reference `review_public_passwords` to badge each review as public, hidden, or contacts-only

### Directory views

- [`OriginsLive`](../../../../lib/chat_web/live/electric_live/origins_live/index.ex) — real-time Electric stream listing of all origins
- [`ReviewsLive`](../../../../lib/chat_web/live/electric_live/reviews_live/index.ex) — real-time Electric stream listing of all reviews
- [`ReviewPublicPasswordsLive`](../../../../lib/chat_web/live/electric_live/review_public_passwords_live/index.ex) — public passwords directory
- [`ReviewPostRightsLive`](../../../../lib/chat_web/live/electric_live/review_post_rights_live/index.ex) — post rights directory
- [`ReviewRevokeRightsLive`](../../../../lib/chat_web/live/electric_live/review_revoke_rights_live/index.ex) — revoke rights directory
- [`ReviewListsLive`](../../../../lib/chat_web/live/electric_live/review_lists_live/index.ex) — review lists directory

Shared components: [`ElectricLive.ShapeReader`](../../../../lib/chat_web/live/electric_live/shape_reader.ex), [`ElectricLive.StreamIndex`](../../../../lib/chat_web/live/electric_live/stream_index.ex).

## Implementation phases

### Phase 1 — Origin entity ✓

See [Origin](pq_origin.done.md).

- [x] `origins` Ecto schema and migration
- [x] Electric publication
- [x] `origin` Electric shape with owner access control
- [x] Origin data context with upsert (LWW)
- [x] Origin validation module
- [x] `OriginSignHash` type, `PrefixedHash` macro
- [x] Origin sandbox LiveView
- [x] Origins directory LiveView

### Phase 2 — Public reviews and moderation pipeline ✓

See [Moderation](pq_review_moderation.done.md) and [Versioning](pq_review_versioning.in_progress.md).

- [x] Hash types (ReviewHash, ReviewSignHash, ReviewPasswordSignHash, etc.)
- [x] All review schemas + migrations (review, review_public_passwords, review_password_candidate, review_post_right, review_revoke_right, review_list, right candidates)
- [x] Electric publication + REVOKE DELETE on content tables
- [x] Right-envelope HKDF context
- [x] Data contexts with LWW upsert
- [x] Validation modules (signature, moderation-proof, author/origin binding, right cross-table binding)
- [x] Electric shapes (review, passwords, rights, candidates, review_list)
- [x] Two-phase candidate promotion for all moderation modes
- [x] Tests (241 passing)
- [x] Review sandbox, reviews directory, origin reviews public viewer
- [x] Ingest-triggered promotion
- [x] Origin moderation sandbox (identity import, queue, approve/reject/revoke)
- [x] `origin_hash` on `review_list`
- [x] Review author sandbox step 5 (moderation proofs, review_list ingest)
- [x] Shared ShapeReader + RequestLog
- [x] Author-side KEM-wrapping verification
- [ ] Review versioning — see [Versioning](pq_review_versioning.in_progress.md)

### Phase 3 — Contacts channel and owner controls

See [Contacts](pq_review_contacts.done.md).

- [x] `review_list_password` — generate once per author, store in User Storage
- [x] `{"review_list_key": [...]}` dialog content type + send to peers
- [x] Contacts reader sandbox
- [ ] Owner-signed authorization for dangerous origin ops (moderation mode, soft delete) — see the Status note under [Origin creation](pq_origin.done.md#origin-creation)
- [ ] Origin keys in User Storage for multi-device access

### Phase 4 — `to_contacts` visibility tier (future)

Distinct from the Phase 3 contacts channel: that one shares `to_public` reviews with contacts, this one
is a review tier that never enters public moderation at all.

- [ ] contacts key infrastructure
- [ ] contacts-only review encryption/decryption
- [ ] depends on broader contacts/trust model design

### Phase 5 — Operational hardening

- [ ] Stale-candidate GC — schedule periodic cleanup via [`ReviewRightCandidate.delete_stale_candidates/1`](../../../../lib/chat/data/review_right_candidate.ex):50
- [ ] Stale *password* candidate GC
- [ ] Clean rejection instead of a 500 for stale HTTP updates — see [Known gaps](#known-gaps-and-defects)
- [ ] Connect the app as a limited (non-superuser) Postgres role so `REVOKE DELETE` takes effect

## Known gaps and defects

Behaviour that diverges from this document, pinned by tests where a failing assertion exists.

### Stale HTTP updates raise instead of being rejected

`validate_timestamp_newer_than_existing/1` marks the changeset `action: :ignore`, which
`Phoenix.Sync.Writer` then hands to `Ecto.Multi.update/4` — which refuses it, so the client gets a
500 rather than a clean 4xx. The peer-sync path handles `:ignore` explicitly
(`Shapes.ReviewList.apply_changeset/2`); the HTTP path does not. Affects `review_list`, `review`,
`origin`, and every other ingestable table. Pinned by
[`electric_controller_review_list_update_test.exs`](../../../../test/chat_web/controllers/electric_controller_review_list_update_test.exs).

### Equal-timestamp updates diverge between node and peers

`validate_timestamp_newer_than_existing/1` reads `get_change/2`, which is `nil` when the cast value
equals the stored one — so an equal timestamp passes locally, while the upsert query's
`owner_timestamp < EXCLUDED` guard makes every peer reject it. `owner_timestamp` is unix seconds, so
two clicks in the same second reach this. `ReviewSandboxLive.ReviewList.fill_password_proof/4` works
around it with `max(previous + 1, now)`. Pinned by the same test file.

### Password candidates are not signature-checked at ingest

[`ReviewPasswordCandidate.Validation.candidate_validate/3`](../../../../lib/chat/data/review_password_candidate/validation.ex) checks the changeset and the
review/author binding, but not `sign_b64`. The signature *is* verified before anything is minted or
wrapped ([`Promotion.Candidates.validate_candidate/1`](../../../../lib/chat/data/review_password_candidate/promotion/candidates.ex)), so nothing forged ever reaches
`review_public_passwords` — but in post/pre mode a lone badly-signed candidate is stored and returns
`{:ok, :pending}`, and nothing ever removes it.

### Two-tier owner/origin split is not enforced

Origin `update` — including `moderation_mode` and `deleted_flag` — is authorized by either the origin
identity's or the owner's signature (see [`validate_origin_update_signature/1`](../../../../lib/chat/data/origin/validation.ex)), so a delegated moderator can change moderation mode or soft-delete the
origin. See the Status note under [Origin creation](pq_origin.done.md#origin-creation).

## Open questions

### 1. Rating system — resolved

Settled by the [Content model](pq_review_moderation.done.md#content-model): rating is position 0 of
the encrypted content array.

### 2. Comment threading

Flat comments or threaded (via `parent_comment_hash`)? Flat is simpler.

### 3. Review editing — resolved

See [Review versioning](pq_review_versioning.in_progress.md). Edits allowed in none/post modes and
pre-mode pending; blocked once pre-mode moderation happens.

### 4. SaaS model

How does the SaaS aspect work? Origin creation subscription, premium moderation, paid analytics, or
the review infrastructure itself as the product.

## Future: to_contacts visibility

`to_public` reviews are already visible to author's contacts regardless of moderation status. A standalone `to_contacts` tier (reviews visible only to contacts, never submitted for public moderation) is a future extension.

Crypto approach: author generates a symmetric `contacts_key`, wraps it for each dialog partner using existing dialog `sender_msg_key`. All contacts-only reviews use this key. Key rotates when contacts change.

This is a separate concern involving the broader contacts/trust model and will be designed independently.

## Source modules

| Layer | Module | Source |
|-------|--------|--------|
| Schema | `Chat.Data.Schemas.Origin` | [`schemas/origin.ex`](../../../../lib/chat/data/schemas/origin.ex) |
| Schema | `Chat.Data.Schemas.Review` | [`schemas/review.ex`](../../../../lib/chat/data/schemas/review.ex) |
| Schema | `Chat.Data.Schemas.ReviewVersion` | [`schemas/review_version.ex`](../../../../lib/chat/data/schemas/review_version.ex) |
| Schema | `Chat.Data.Schemas.ReviewPublicPassword` | [`schemas/review_public_password.ex`](../../../../lib/chat/data/schemas/review_public_password.ex) |
| Schema | `Chat.Data.Schemas.ReviewPasswordCandidate` | [`schemas/review_password_candidate.ex`](../../../../lib/chat/data/schemas/review_password_candidate.ex) |
| Schema | `Chat.Data.Schemas.ReviewList` | [`schemas/review_list.ex`](../../../../lib/chat/data/schemas/review_list.ex) |
| Schema (macro) | `Chat.Data.Schemas.ReviewRight` | [`schemas/review_right.ex`](../../../../lib/chat/data/schemas/review_right.ex) |
| Schema | `Chat.Data.Schemas.ReviewPostRight` | [`schemas/review_post_right.ex`](../../../../lib/chat/data/schemas/review_post_right.ex) |
| Schema | `Chat.Data.Schemas.ReviewRevokeRight` | [`schemas/review_revoke_right.ex`](../../../../lib/chat/data/schemas/review_revoke_right.ex) |
| Schema | `ReviewPostRightCandidate` / `ReviewRevokeRightCandidate` | [`schemas/review_right_candidate.ex`](../../../../lib/chat/data/schemas/review_right_candidate.ex) |
| Validation | `Chat.Data.Origin.Validation` | [`origin/validation.ex`](../../../../lib/chat/data/origin/validation.ex) |
| Validation | `Chat.Data.Review.Validation` | [`review/validation.ex`](../../../../lib/chat/data/review/validation.ex) |
| Validation | `Chat.Data.ReviewPublicPassword.Validation` | [`review_public_password/validation.ex`](../../../../lib/chat/data/review_public_password/validation.ex) |
| Validation | `Chat.Data.ReviewPasswordCandidate.Validation` | [`review_password_candidate/validation.ex`](../../../../lib/chat/data/review_password_candidate/validation.ex) |
| Validation | `Chat.Data.ReviewList.Validation` | [`review_list/validation.ex`](../../../../lib/chat/data/review_list/validation.ex) |
| Validation (macro) | `Chat.Data.ReviewRight.Validation` | [`review_right/validation.ex`](../../../../lib/chat/data/review_right/validation.ex) |
| Validation | `Chat.Data.ReviewRightCandidate.Validation` | [`review_right_candidate/validation.ex`](../../../../lib/chat/data/review_right_candidate/validation.ex) |
| Versioning | `Chat.Data.Review.Versioning` | [`review/versioning.ex`](../../../../lib/chat/data/review/versioning.ex) |
| Data context | `Chat.Data.Origin` | [`origin.ex`](../../../../lib/chat/data/origin.ex) |
| Data context | `Chat.Data.Review` | [`review.ex`](../../../../lib/chat/data/review.ex) |
| Data context | `Chat.Data.ReviewPublicPassword` | [`review_public_password.ex`](../../../../lib/chat/data/review_public_password.ex) |
| Data context | `Chat.Data.ReviewPasswordCandidate` | [`review_password_candidate.ex`](../../../../lib/chat/data/review_password_candidate.ex) |
| Data context | `Chat.Data.ReviewRightCandidate` | [`review_right_candidate.ex`](../../../../lib/chat/data/review_right_candidate.ex) |
| Data context | `Chat.Data.ReviewPostRight` | [`review_post_right.ex`](../../../../lib/chat/data/review_post_right.ex) |
| Data context | `Chat.Data.ReviewRevokeRight` | [`review_revoke_right.ex`](../../../../lib/chat/data/review_right.ex) |
| Data context | `Chat.Data.ReviewList` | [`review_list.ex`](../../../../lib/chat/data/review_list.ex) |
| Promotion | `Chat.Data.ReviewPasswordCandidate.Promotion` | [`promotion.ex`](../../../../lib/chat/data/review_password_candidate/promotion.ex) |
| Promotion | `Promotion.Candidates` | [`promotion/candidates.ex`](../../../../lib/chat/data/review_password_candidate/promotion/candidates.ex) |
| Crypto | `Chat.Data.ReviewRightEnvelope` | [`review_right_envelope.ex`](../../../../lib/chat/data/review_right_envelope.ex) |
| Shape registry | `Chat.Data.Shapes` | [`shapes.ex`](../../../../lib/chat/data/shapes.ex) |
| Types | `Consts` (prefixes) | [`types/consts.ex`](../../../../lib/chat/data/types/consts.ex) |
| Test fixtures | `Chat.Test.ReviewFixtures` | [`test/support/review_fixtures.ex`](../../../../test/support/review_fixtures.ex) |

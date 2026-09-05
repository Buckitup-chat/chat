# PQ Review Versioning

Review editing via the two-table versioning pattern
(see [03_data_versioning.md](../../invariants/03_data_versioning.md)).

## Review versioning

Review editing follows the same two-table versioning pattern as `user_storage` / `dialog_messages`:
a master table (`review`) holds the current tip, a versions table (`review_versions`) holds every
superseded version. On edit, a transaction archives the outgoing tip into `review_versions` and
rewrites the master row with the new content and `parent_sign_hash` pointing to the archived
version. Because `sign_b64` signs `parent_sign_hash`, the chain is tamper-evident.

### What changes on edit

The `review_password` is per-review, not per-version — the same AES-256-GCM key encrypts every
version's `content_b64`. An edit re-encrypts new content with the same key, producing new
`content_b64`, `sign_b64`, and `sign_hash`. The `review_hash` (the review's stable identity)
stays the same.

### What stays unchanged

- **`review_public_passwords`** — the password is per-review; an edit doesn't affect it
- **`review_post_right` / `review_revoke_right`** — wrap the password, not the content
- **`review_password_candidate`** + promotion pipeline — unchanged
- **`review_list`** — references `review_hash`, not a specific version
- **Content model** — `[rating, placeholder, content]` stays the same, just new ciphertext per edit

### Edit rules by moderation mode

| Mode | Editable? | Rationale |
|------|-----------|-----------|
| **none** | yes | Auto-promoted; no gatekeeper. Origin has no revoke right, but content is the author's. |
| **post** | yes | Already public; origin has revoke right if edited content violates policy. |
| **pre** (pending) | yes | Origin hasn't acted yet; they evaluate the latest version when they decide. |
| **pre** (moderated) | **no** | Origin explicitly approved or rejected specific content. Allowing edits after moderation would undermine the pre-moderation guarantee. |

**Pre-mode lock detection.** The origin's moderation action creates a `review_public_passwords` row
(non-null password for approval, null for rejection). The server rejects a review update when the
origin's `moderation_mode` is `pre` AND any `review_public_passwords` row exists for the review's
`review_hash`.

### Versioning module

`Chat.Data.Review.Versioning` — a dedicated module (not reusing `Dialog.Versioning`) following the
same `archive_and_insert` / `archive_and_update` / `archive_changeset` transaction pattern. The
review shape (`Shapes.Review`) drops the `persist:` macro and implements `sync_persist/2` directly
to call `Review.Versioning`. The HTTP ingest path wires `pre_apply` into `ingest_configure_writer`
for the same archiving logic.

## Data model

### review_versions

Append-only archive of superseded review versions. Same structure as the `user_storage_versions` /
`dialog_messages_versions` pattern.

```
review_versions
├── review_hash           — PK part 1
├── sign_hash             — PK part 2 (ReviewSignHash, version identity)
├── origin_hash           — TEXT NOT NULL, immutable context
├── author_hash           — TEXT NOT NULL, immutable context
├── content_b64           — BYTEA NOT NULL, this version's AES-256-GCM encrypted content
├── deleted_flag           — BOOLEAN NOT NULL DEFAULT false
├── parent_sign_hash      — ReviewSignHash, FK → review_versions(sign_hash), nullable for first version
├── owner_timestamp       — BIGINT NOT NULL
└── sign_b64              — BYTEA NOT NULL, author's ML-DSA-87 signature
```

PK: `(review_hash, sign_hash)`. Self-referential FK on `parent_sign_hash`. DELETE revoked at role
level. The master `review` table also carries an FK: `review.parent_sign_hash →
review_versions.sign_hash`.

Electric-published for audit/history sync.

## Electric shape

### review_versions shape

Read-only archive — no ingest path (rows are created server-side by the versioning transaction).
Synced by `review_hash` or `origin_hash`.

## Implementation

- [ ] `review_versions` migration + Electric publication + REVOKE DELETE
- [ ] FK `review.parent_sign_hash → review_versions.sign_hash`
- [ ] `Chat.Data.Schemas.ReviewVersion` — same fields as `Review`, PK: `(review_hash, sign_hash)`, uses existing `ReviewSignHash`
- [ ] `Chat.Data.Review.Versioning` — `archive_and_insert/3`, `archive_and_update/3`, `archive_changeset/1` (dedicated module, not reusing `Dialog.Versioning`)
- [ ] `Chat.Data.Review` context — `update_review_with_versioning/2`, `insert_review_with_conflict/2`
- [ ] `Shapes.Review` — drop `persist:` macro, implement `sync_persist/2` with versioning; add `versions_schema/0 → ReviewVersion`; wire `pre_apply` into `ingest_configure_writer`
- [ ] `Review.Validation` — `validate_edit_allowed/1`: reject update when `moderation_mode == "pre"` AND any `review_public_passwords` row exists for the `review_hash`
- [ ] Tests: version chain creation, pre-mode lock after moderation, none/post mode edit allowed, tamper-evident chain verification

## Source modules

| Layer | Module | Source |
|-------|--------|--------|
| Schema | `Chat.Data.Schemas.ReviewVersion` | [`schemas/review_version.ex`](../../../../lib/chat/data/schemas/review_version.ex) |
| Versioning | `Chat.Data.Review.Versioning` | [`review/versioning.ex`](../../../../lib/chat/data/review/versioning.ex) |

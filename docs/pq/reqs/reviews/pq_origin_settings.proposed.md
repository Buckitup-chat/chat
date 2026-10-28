# PQ Origin Settings

Unencrypted key-value storage per origin, Electric-synced, so the server knows how to operate for a given origin.

## Goal

Provide a flexible settings table for origins that avoids re-signing the entire origin row when only a setting changes and requires no migration for new keys.

---

## Data Model

### origin_settings

```
origin_settings
├── origin_hash     — TEXT PK, FK → origins(origin_hash) ON DELETE CASCADE
├── key             — TEXT PK (e.g. "review_access")
├── value           — TEXT NOT NULL
├── deleted_flag    — BOOLEAN NOT NULL DEFAULT false
├── owner_timestamp — BIGINT NOT NULL (LWW)
├── sign_b64        — BYTEA NOT NULL (signed by origin identity)
```

Composite primary key `(origin_hash, key)`. Each row is one setting for one origin.

**Signing:** origin identity signs each row — same identity as the `origins` table. Updates accept either the origin identity's or the owner's signature (same dual-auth as origin updates).

**No `sign_hash`.** The row is uniquely identified by its composite PK. The Shape behaviour's `fingerprint/1` falls back to hashing `sign_b64` directly.

**Values are text.** Each key's validation logic interprets the value in Elixir, not via DB constraints, so new keys need no migration.

Migration: [`20261013100000_create_origin_settings`](../../../../priv/repo/migrations/20261013100000_create_origin_settings.exs). Added to `electric_publication_default`. DELETE revoked.

---

## Known Keys

| Key | Values | Default (when absent) | Purpose |
|-----|--------|-----------------------|---------|
| `review_access` | `open`, `invite_only` | `open` | Controls who can enter the review pipeline. See [pq_review_write_tokens](pq_review_write_tokens.in_progress.md#review-access-mode--per-origin-policy). |
| `auth_token` | string (16–256 chars) | *none* | Shared secret gating `POST /r/api/token/create`. Origin owner sets it; callers pass it as `Authorization: Bearer <token>`. Required — token creation is rejected when no `auth_token` is configured. |

---

## Electric Shape

Shape: [`Chat.Data.Shapes.OriginSetting`](../../../../lib/chat/data/shapes/origin_setting.ex). Synced — devices filter by origins they hold keys for.

Required parents: `user_card` (origin identity) + `origin` row.

Access control: insert and update require origin identity or owner auth, plus the standard device WriteGate.

---

## Source Modules

| Layer | Module | Source |
|-------|--------|--------|
| Schema | `Chat.Data.Schemas.OriginSetting` | [`schemas/origin_setting.ex`](../../../../lib/chat/data/schemas/origin_setting.ex) |
| Validation | `Chat.Data.OriginSetting.Validation` | [`origin_setting/validation.ex`](../../../../lib/chat/data/origin_setting/validation.ex) |
| Data context | `Chat.Data.OriginSetting` | [`origin_setting.ex`](../../../../lib/chat/data/origin_setting.ex) |
| Shape | `Chat.Data.Shapes.OriginSetting` | [`shapes/origin_setting.ex`](../../../../lib/chat/data/shapes/origin_setting.ex) |

---

## Status

Proposed.

## References

- [pq_origin](pq_origin.done.md) — origin entity, creation, ownership
- [pq_review_write_tokens](pq_review_write_tokens.in_progress.md) — consumes `review_access` setting

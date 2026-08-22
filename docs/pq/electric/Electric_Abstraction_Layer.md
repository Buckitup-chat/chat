# Electric Abstraction Layer

> **Status: historical design intent.** Everything below through "Rule of Thumb" is the original proposal that motivated the layering — schema/validation/ingestion/transport separation. The naming it sketches (`authorize/2`, `validate/3`, `apply/3` as a formal behaviour) was not implemented verbatim. See [Current Implementation](#current-implementation) at the bottom for what was actually built and how it maps back to these principles.

## Goal

Keep **schemas simple** while still giving each model a **clear, explicit ingestion policy**.

The implementation should avoid a single universal ingestion function for every model. Instead, shared mechanics should live in small reusable helpers, while each model keeps its own ingestion rules and configuration close to the model itself.

## Design Principles

- **Schemas stay small**
  - Define fields, primary keys, and local changeset constraints.
  - Avoid putting transport or sync policy into schema modules.

- **Ingestion is model-specific**
  - Each model can define how it should be accepted, validated, normalized, and written.
  - Different models may need different conflict handling, parent checks, or timestamp rules.

- **Shared behavior is only for shared traits**
  - Use protocols for structural capabilities such as signature verification or timestamp extraction.
  - Use helpers for shared decoding and repeated low-level mechanics.

- **Avoid one-size-fits-all dispatch**
  - Do not force every model through the same validation/write function.
  - Prefer a small behaviour with per-model implementations.

## Recommended Layering

### 1. Schema Layer

Owns only the database shape.

Examples:

- `Chat.Data.Schemas.UserCard`
- `Chat.Data.Schemas.UserStorage`

Typical responsibilities:

- `Ecto.Schema`
- changeset validation for structural constraints
- uniqueness and DB-oriented checks
- protocol implementations for structural traits

### 2. Shared Validation Layer

Owns reusable validation primitives.

Examples:

- `Chat.Data.User.Validation`
- `Chat.Data.Integrity`

Good fit for:

- signature verification
- timestamp comparison
- shared auth checks
- helpers that apply across multiple models

### 3. Ingestion Policy Layer

Owns the per-model ingestion rules.

Recommended shape:

- one module per model
- one behaviour defining common callbacks
- explicit model-specific config and logic

Example responsibilities:

- whether inserts/updates/deletes are accepted
- how incoming payloads are normalized
- what gets validated before write
- conflict strategy
- parent existence checks or dependency checks

### 4. Generic Transport / Decoding Layer

Owns generic wire-format handling only.

Examples:

- `ChatWeb.Utils.IngestUtil`

Good fit for:

- hex/base64 decoding
- mutation payload normalization
- format-specific decoding that is not model-specific

## Suggested Behaviour Shape

A per-model ingestion behaviour could look conceptually like this:

- `authorize/2`
- `validate/3`
- `apply/3`

Optional callbacks:

- `normalize/1`
- `conflict_opts/1`
- `write_strategy/1`

This keeps the ingestion contract consistent without making the implementation identical.

## Example Mapping

### `UserCard`

Needs:

- signature validation
- timestamp monotonicity checks
- insert/update/delete branching
- schema-level integrity checks

### `UserStorage`

Needs:

- signature validation via owning user
- parent `user_card` existence checks
- value size validation
- different update/write behavior from `UserCard`

These are related, but not identical enough to justify one shared all-purpose ingestion function.

## What Should Be Shared

Share only the parts that are truly common:

- payload decoding
- signature verification primitives
- timestamp extraction protocol
- logging helpers
- error formatting

## What Should Stay Per-Model

Keep per-model modules for:

- validation policy
- auth policy
- write policy
- conflict resolution
- dependency checks
- field-specific normalization

## Practical Recommendation

Use this split:

- **schemas**: minimal and declarative
- **shared validation helpers**: reusable primitives
- **per-model ingestion modules**: explicit policy and config
- **generic decoding helpers**: transport-level normalization only

This gives you centralization where it helps, while preserving the ability for each model to define its own ingestion rules.

## Rule of Thumb

If the logic answers:

- "What is this data?" -> put it near the schema or in a protocol
- "How should this model be ingested?" -> put it in a per-model ingestion module
- "How is this payload decoded?" -> put it in a shared utility

## Current Implementation

What actually shipped keeps the four-layer split above but with different names and one added pipeline (peer sync), since Electric rows arrive two ways — through the HTTP ingest endpoint and by direct replication between peers.

### Behaviour: `Chat.Data.Shapes.Shape`

`lib/chat/data/shapes/shape.ex` is the one behaviour every model implements (one module per model, e.g. `Chat.Data.Shapes.UserCard`, `Chat.Data.Shapes.FileChunk`) — this is the "Ingestion Policy Layer" from the design above, concretized:

| Callback | Pipeline | Purpose |
|---|---|---|
| `shape_name/0`, `schema_module/0`, `versions_schema/0` | both | identity |
| `sync_required_parents/2`, `sync_validate_parent/2` | peer sync | dependency/parent checks |
| `sync_derive_fields/1` | peer sync | normalization |
| `sync_persist/2`, `sync_after_persist/3` | peer sync | write policy |
| `ingest_configure_writer/2` | HTTP ingest | wires the model into `Phoenix.Sync.Writer.allow/4` |

### HTTP ingest: `ingest_configure_writer/2`

Each model's `ingest_configure_writer/2` calls `Phoenix.Sync.Writer.allow(writer, SchemaModule, accept: ..., check: ..., validate: ...)`. `ChatWeb.ElectricController.ingest/2` (`lib/chat_web/controllers/electric_controller.ex`) folds every shape's writer config together and hands the batch to `Phoenix.Sync.Writer.apply/4`.

- `check:` is PoP — verifies the request's challenge signature (e.g. `Chat.Data.User.Validation.user_card_allowed/2`).
- `validate:` is signature + business-rule validation, always a 3-arity function `(struct_or_changeset, changes, operation) -> Ecto.Changeset` — this is the closest thing to the sketched `validate/3`, but it is not a formal behaviour callback, just a convention. Every shape module supplies its own, differently named: `user_card_validate/3`, `file_chunk_validate/3`, `receipt_validate/3`, `origin_validate/3`, `message_validate_with_versioning/3`, etc. (two review-right-candidate shapes inline an anonymous 3-arity `fn` instead of naming a function). All of them funnel through `Chat.Data.Integrity.verify_signature/1`, most via the shared `Chat.Data.User.Validation.validate_signature/1` helper (despite living in the `User` namespace, it's used by File, Dialog, Origin, and Review validation modules too).
- Two models — `review_post_right` and `review_revoke_right` — don't override `ingest_configure_writer/2` at all (they inherit `Shape`'s no-op default), so they aren't directly HTTP-ingestible; they're only ever written server-side via promotion from their `_candidate` tables (`lib/chat/data/review_right_candidate/validation.ex`, `lib/chat/data/review_password_candidate/promotion.ex`), which call `Integrity.verify_signature/1` directly rather than through a shape's `validate:` callback.

### Shared validation layer

`Chat.Data.Integrity` (signature primitives) and the various `Chat.Data.<Model>.Validation` modules (per-model rules, calling the shared `validate_signature/1` / `validate_timestamp_newer_than_existing/1` helpers) fill the "Shared Validation Layer" role — this part matches the design doc closely.


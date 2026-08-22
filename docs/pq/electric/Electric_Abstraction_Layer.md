# Electric Abstraction Layer

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


# Branching

> Status: **not yet implemented** — design sketch.

## Problem

Two things in one shape:

1. **Replies**: a user wants to respond to a specific earlier message, not just the tip — the UI should render the reply anchored to its target.
2. **Concurrent forks**: two peers, observing the same `prev_message_uuid` as the tip, both send a new message. [Ordering](./04_ordering.md) admits this as a legitimate fork rather than silently dropping one side.

Both collapse to the same structural primitive: a message that points to a non-tip parent.

## Approach

Extend the [ordering](./04_ordering.md) schema with a second, optional pointer:

| Field | Role |
|---|---|
| `prev_message_uuid` | Timeline predecessor — tip as observed at send time (never null except genesis). |
| `reply_to_uuid` | Explicit reply target — the `message_uuid` this message is authored as a response to. Null for top-of-timeline messages. |

Both fields are covered by `sign_b64`, so a reply target is tamper-proof and can be verified locally.

Branch detection is read-side: when multiple messages share the same `prev_message_uuid`, they are siblings. The UI chooses a rendering:

- **Dialog / chat**: linearize siblings by UUIDv7 timestamp (cheap, deterministic, identical on every peer).
- **Threaded view**: group by `reply_to_uuid` and render children beneath their target.

The storage layer does **not** pick one branch as canonical. It preserves all siblings; resolution is a UI concern.

## Relationship to data versioning

[Data versioning](./03_data_versioning.md) also chains via `parent_sign_hash`, but constrains the chain to a single author. Messages are multi-author, so the equivalent pointer (`prev_message_uuid`) does not guarantee linearity — that is exactly what enables branching.

## Where this touches existing work

- **Existing mention**: the [README](./README.md) calls this "responding to custom message_uuid".
- **Primitive reused**: [04_ordering.md](./04_ordering.md) — branching is an add-on to the ordering chain, not a separate mechanism.
- **Original dialog draft**: [pq_dialogs.md](../../reqs/pq_dialogs.md) leaves "polymorphic/embedded content" and "read versions" open; branching is the structural piece under both.

## Invariants

- `reply_to_uuid`, when present, must resolve to a known message in the same conversation. Cross-conversation replies are rejected at ingest.
- Branches are first-class: no row is deleted to resolve a fork. "Winning" a branch is purely a display-layer decision.
- A reply cannot point to a descendant of itself (acyclicity) — enforced at ingest by walking the chain, bounded by `owner_timestamp` monotonicity in practice.

## Open questions

- Depth limit on reply chains (or none — recursive rendering handles it).
- Whether `reply_to_uuid` should resolve across conversations (e.g., forwarding). Current assumption: no.
- Display policy when a reply target arrives *after* the reply (out-of-order delivery): render as pending until the target syncs.

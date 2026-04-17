# Reactions

> Status: **not yet implemented** — design sketch.

## Problem

A reaction (emoji tap, like, read-receipt, delivery-receipt) is a tiny, append-only statement *by one user about one message*. It must:

- Attribute reliably to its author (same signing story as every other PQ row).
- Not bloat the message row with per-observer fields.
- Support many reactions per message from many users over time, with removal.
- Include **read receipts** — a read is just a reaction of a fixed kind.

## Approach

A dedicated `reactions` table, with one row per (user, message, kind) tuple. Reactions are independent rows keyed by their target, not embedded in the message — this keeps message rows immutable and avoids write contention.

| Field | Role |
|---|---|
| `conversation_hash` | Scope — same as the target message's conversation. |
| `target_message_uuid` | The message being reacted to. |
| `author_hash` | `user_hash` of the reactor. |
| `kind` | Short enum tag: `:read`, `:delivered`, `:like`, `:emoji`, ... |
| `payload` | Kind-dependent (e.g. emoji codepoint for `:emoji`; null for `:read`). |
| `owner_timestamp` | Monotonic — removal is a newer row with `deleted_flag: true`. |
| `sign_b64` | ML-DSA-87 signature over the row. |

Removal (unreact) follows the same soft-delete pattern as `user_cards`: a fresh signed row with `deleted_flag: true` and a higher `owner_timestamp` supersedes the prior state. This is compatible with Electric's LWW semantics and the peer-sync write strategy in [electric_network_sync.md](../../reqs/electric_network_sync.md).

**Read receipts** deserve a note: they are structurally reactions of `kind: :read`, but semantically privileged — the UI consumes them to compute unread counters and delivery indicators. Treating them as a reaction keeps the storage uniform; the UI layer picks them out by `kind`.

## Where this touches existing work

- **Flagged as open**: [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md) lists "message read status" and "proves/likes?" as unsolved.
- **Existing mention**: the [README](./README.md) groups reactions with "including reading" — one row type for both.
- **Integrity**: reuses [02_integrity.md](./02_integrity.md) verbatim; a reaction is just a small signed row.

## Invariants

- `(conversation_hash, target_message_uuid, author_hash, kind)` is the unique key — a user's like or read state for one message is a single logical fact, not a log.
- `target_message_uuid` must resolve in the same conversation. Server rejects dangling reactions at ingest.
- `author_hash` must match the PoP signer — a user cannot react on behalf of another.
- Read receipts are publishable to the conversation, not private to the sender. Privacy is a policy question deferred to the conversation model, not the storage model.

## Open questions

- Whether to surface `:read` as a separate Electric shape for efficiency (high-frequency writes vs. lower-frequency "real" reactions).
- Bulk-read-up-to-message-X — one row per message or one aggregate row with a `through_message_uuid`? The latter is cheaper but harder to reconcile across peers.
- Retention: prune old receipts once a higher one supersedes, or keep history for auditability?

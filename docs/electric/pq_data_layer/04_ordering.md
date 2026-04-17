# Ordering

> Status: **not yet implemented** — shape of the solution described; no tables exist.

## Problem

Dialog and room messages are authored concurrently by multiple peers and delivered over an eventually-consistent sync layer. The data layer must let any peer reconstruct a **total causal order** per conversation without a central sequencer, and must make it impossible for a peer to silently insert a message "between" two earlier ones after the fact.

This is distinct from [data versioning](./03_data_versioning.md): versioning orders revisions of a single key by a single author; ordering threads independent authors' messages into a shared timeline.

## Approach

Each message carries two identifiers forming a hash-linked chain *per conversation*:

| Field | Role |
|---|---|
| `message_uuid` | UUIDv7 — author-generated, time-ordered, globally unique. |
| `prev_message_uuid` | `message_uuid` of the message this one observed as the tip when authored. Null only for the very first message in the conversation. |
| `sign_b64` | Covers both fields, so the link is tamper-evident (same pattern as [integrity](./02_integrity.md)). |

Reading the history is a DAG walk rooted at the tip: each node names its predecessor, and because `sign_b64` signs `prev_message_uuid`, a peer cannot retroactively "adopt" a different parent. UUIDv7's embedded timestamp breaks ties when two authors legitimately observed the same tip (concurrent sends) — the older one wins for display order; both remain reachable.

Compared to [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md)'s current draft (which lists `message_uuid` but not `prev_message_uuid`), the PQ data layer adds the hash-link requirement because Electric sync offers no guarantee about delivery order.

## Where this touches existing work

- **Current dialog sketch**: [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md) — flags "message order mergeble" as an open problem; this doc is the proposed answer.
- **Integrity primitive it reuses**: [02_integrity.md](./02_integrity.md)
- **Why Electric alone isn't enough**: [electric_network_sync.md §Conflict Resolution](../../reqs/electric_network_sync.md) — LWW per row is fine for `user_storage`, insufficient for a shared timeline.

## Invariants

- A message row is rejected on ingest if `prev_message_uuid` does not resolve to a known message in the same conversation (or is null for the genesis message).
- `sign_b64` must cover `(conversation_id, message_uuid, prev_message_uuid, sender_hash, payload_hash, owner_timestamp)` — anything less lets a peer swap parents.
- Forks are allowed at the data layer (two peers signing off the same `prev_message_uuid`) but are surfaced explicitly to the UI; see [05_branching.md](./05_branching.md).

## Open questions

- Schema: one table per conversation vs. one global `messages` table with `conversation_hash` column.
- Where `conversation_hash` comes from — reuse `dialog_hash` from [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md)?
- Catch-up protocol: when a peer joins mid-conversation, how do tails get backfilled efficiently over Electric shapes (likely a per-conversation shape with `WHERE conversation_hash = ?`).
- Garbage-collection / retention story for very long conversations.

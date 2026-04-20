# Ordering

> Status: **not yet implemented** — shape of the solution described; no tables exist.

## Problem

Dialog and room messages are authored concurrently by multiple peers and delivered over an eventually-consistent sync layer. The data layer must let any peer reconstruct a **total causal order** per conversation without a central sequencer, and must make it impossible for a peer to silently insert a message "between" two earlier ones after the fact.

This is distinct from [data versioning](./03_data_versioning.md): versioning orders revisions of a single key by a single author; ordering threads independent authors' messages into a shared timeline.

## Approach

Every message row carries two identifiers of the **same shape**, forming a hash-linked chain *per conversation*:

| Field            | Role                                                                                                                                                 |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `message_id`     | `dmsg_` + UUIDv7 — author-generated, time-ordered, globally unique (shape already defined by [pq_dialogs.md](../../reqs/pq_dialogs.md)).             |
| `ref_message_id` | `message_id` of the message the author observed as the tip when composing this one. `NULL` only for the genesis message of the conversation.        |
| `sign_b64`       | ML-DSA-87 signature covering both fields (and the rest of the signable columns), so the link is tamper-evident — same pattern as [integrity](./02_integrity.md). |

The `<thing>_id` / `ref_<thing>_id` shape is the convention: the primary identifier and the reference have identical type and prefix, so a reader never has to ask "what does this point at." `ref_message_id` always resolves to another `dialog_messages.message_id` in the same `dialog_hash`.

Reading history is a DAG walk rooted at the tip: each node names its predecessor via `ref_message_id`, and because `sign_b64` covers `ref_message_id`, a peer cannot retroactively "adopt" a different parent — the signature would break. UUIDv7's embedded timestamp breaks ties when two authors legitimately observed the same tip (concurrent sends); the older one wins for display order, but both remain reachable through their siblings' `ref_message_id` links.

`ref_message_id` is **not** a reply pointer (explicit replies are owned by [05_branching.md](./05_branching.md) as `reply_to_message_id`). It is the *causal context* — "this is the tip I had seen when I pressed send" — analogous to a git parent. A reply targets a semantic ancestor; `ref_message_id` targets the most recent observed predecessor regardless of semantics.

Compared to the current draft of [pq_dialogs.md](../../reqs/pq_dialogs.md) (which lists `message_id` but no causal-context field), the PQ data layer adds `ref_message_id` because Electric sync offers no guarantee about delivery order and `parent_sign_hash` only chains revisions *by the same author*.

## Where this touches existing work

- **Current dialog sketch**: [pq_dialogs.md](../../reqs/pq_dialogs.md) — flags cross-author ordering as an open problem and forward-references this doc.
- **Integrity primitive it reuses**: [02_integrity.md](./02_integrity.md) — signature coverage makes the chain tamper-evident.
- **Why Electric alone isn't enough**: [electric_network_sync.md §Conflict Resolution](../../reqs/electric_network_sync.md) — LWW per row is fine for `user_storage`, insufficient for a shared timeline.
- **Versioning vs. ordering**: [03_data_versioning.md](./03_data_versioning.md) chains revisions of one row by one author (`parent_sign_hash`); this doc chains distinct messages across authors (`ref_message_id`).

## Invariants

- A message row is rejected on ingest if `ref_message_id` does not resolve to a known message in the same `dialog_hash` (or is `NULL` for the genesis message).
- `sign_b64` must cover at minimum `(dialog_hash, message_id, ref_message_id, sender_hash, content_b64, owner_timestamp, deleted_flag)` — anything less lets a peer swap parents or retarget across dialogs.
- `ref_message_id` must belong to the same `dialog_hash` as `message_id`. Cross-dialog references are forbidden and MUST be rejected at ingest without decryption.
- UUIDv7 ordering is advisory for *display*; the DAG formed by `ref_message_id` is authoritative for *causality*. Two messages with out-of-order UUIDv7 timestamps but a valid `ref_message_id` link are legal (clock skew, offline authoring).
- Forks are allowed at the data layer (two peers signing off the same `ref_message_id`) but are surfaced explicitly to the UI; sibling resolution and branch rendering are owned by [05_branching.md](./05_branching.md).
- `ref_message_id` is orthogonal to `parent_sign_hash`: edits to a message do **not** change its `ref_message_id` (causal context is fixed at first authoring), whereas `parent_sign_hash` advances with each edit.

## Ingest rules

1. **Parent-known check.** Reject if `ref_message_id IS NOT NULL` and no row with that `message_id` is locally present for the same `dialog_hash`. Out-of-order delivery implies a pending queue; see [02_integrity.md](./02_integrity.md) for the deferred-verify pattern.
2. **Signature check.** Verify `sign_b64` under `sender_hash`'s `sign_pkey` (fetched from `user_cards`). Covers `ref_message_id`, so any post-hoc reparenting fails.
3. **Genesis uniqueness.** At most one message per `dialog_hash` may have `ref_message_id = NULL`. A second genesis row is a protocol violation; clients surface it as a fork at the root.
4. **No self-reference.** `ref_message_id ≠ message_id`.

## Open questions

- **Schema shape.** One table per conversation vs. one global `dialog_messages` table with `dialog_hash` column. Current direction from [pq_dialogs.md](../../reqs/pq_dialogs.md): single table, `dialog_hash` as filter.
- **Conversation scope.** `ref_message_id` is defined per `dialog_hash`; the same mechanism extends to rooms once `room_hash` lands in `pq_rooms.md`.
- **Catch-up protocol.** When a peer joins mid-conversation, tails must be backfilled so `ref_message_id` can resolve. Likely a per-conversation Electric shape with `WHERE dialog_hash = ?` plus a bounded pending queue for rows whose `ref_message_id` has not yet arrived.
- **Malicious stale references.** An author can deliberately point `ref_message_id` at an old tip to fork the DAG even when fresher tips are visible. Detectable (the fork is explicit) but not preventable; rendering policy is a UI concern owned by [05_branching.md](./05_branching.md).
- **Garbage collection.** Pruning old messages breaks `ref_message_id` resolution for anything downstream. Retention story is owned by [08_snapshots.md](./08_snapshots.md); until then, assume append-only.

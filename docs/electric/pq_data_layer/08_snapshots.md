# Snapshots

> Status: **not yet implemented** — design sketch. Depends on [ordering](./04_ordering.md), [branching](./05_branching.md), and [reactions](./06_reactions.md) being in place.

## Problem

A peer needs a way to say **"this is the full state of the conversation as I saw it at time T"** — signed, portable, and verifiable by any other peer without replaying every message. Uses:

- **Archival / export** — a user wants a durable, authentic record of a conversation.
- **Catch-up accelerator** — a joining peer can trust a snapshot's tip rather than walking the full log.
- **Dispute resolution** — "this conversation included these messages" is now a signed artifact, not a claim.

## Approach

A **snapshot** is a signed row that references the full reachable graph of `(message_uuid, sign_hash)` pairs for a conversation as known to its author at snapshot time.

| Field | Role |
|---|---|
| `conversation_hash` | Scope. |
| `author_hash` | Who took the snapshot. |
| `taken_at` | `owner_timestamp` at snapshot time. |
| `graph_root_hash` | Merkle root over the sorted list of `(message_uuid, sign_hash)` pairs + reactions. |
| `tip_uuids` | List of tip `message_uuid`s (multiple if the conversation is forked — see [branching](./05_branching.md)). |
| `graph_payload` | The full `(message_uuid, sign_hash, parent_uuid, reply_to_uuid)` list, plus reaction hashes. Can be inlined for small conversations or stored by `graph_root_hash` in User Storage — same split as [content polymorphism](./07_content_polymorphism.md). |
| `sign_b64` | ML-DSA-87 over everything above. |

Verification of a snapshot:

1. Recompute `graph_root_hash` from `graph_payload`; compare.
2. Verify `sign_b64` with `author_hash`'s `sign_pkey` (fetched from [user_cards](./02_integrity.md)).
3. For any referenced message the verifier already holds, confirm its `sign_hash` matches the snapshot's entry — detects tampering on *either* side.

The snapshot is a peer's honest assertion about what it saw. It is not proof that those messages existed for *everyone* — but two peers' snapshots at the same `taken_at` should agree on their intersection.

## Relationship to other problems

- **Built on**: `sign_hash` from [integrity](./02_integrity.md), `message_uuid` / `prev_message_uuid` from [ordering](./04_ordering.md), `reply_to_uuid` from [branching](./05_branching.md), reaction rows from [reactions](./06_reactions.md).
- **Storage channel**: the graph payload follows the same inline-vs-blob rule as [content polymorphism](./07_content_polymorphism.md) — small graph inline, large graph out-of-band in User Storage.
- **Not a consensus mechanism**: snapshots are per-author attestations, not a shared agreement. Two peers can produce divergent snapshots if they observed different tips; comparing them is how divergence is detected.

## Where this touches existing work

- **Existing mention**: [README](./README.md) — "snapshot of conversation state signed by peer [full graph of message_uuids and sign_hashes]".
- **Originally flagged**: implicit in [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md)'s open problems (none of which can be fully resolved without a checkpointing story).

## Invariants

- A snapshot's `graph_payload` must be complete for the conversation — partial snapshots are a different feature (range snapshots) and would be a new row type.
- `graph_root_hash` is deterministic: same set of `(message_uuid, sign_hash)` pairs, same root, independent of traversal order. Pairs are sorted by `message_uuid` before hashing.
- Snapshots are append-only — a peer may publish many over time; none are mutated.

## Open questions

- Frequency / policy: on-demand vs. periodic vs. pinned-by-UI.
- Can a snapshot be partial (e.g., "everything since `message_uuid = X`")? Useful for large conversations, but doubles the verification logic.
- Do we need a "snapshot of snapshots" — a peer attesting to a canon set of snapshots? Probably overkill for now.
- Interaction with reaction retention (see [06_reactions.md](./06_reactions.md)) — if old receipts are pruned, older snapshots' graph roots won't re-verify; either pin reactions referenced by live snapshots, or accept that old snapshots age out of verifiability.

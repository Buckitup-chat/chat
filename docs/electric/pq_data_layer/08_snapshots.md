# Snapshots

> Status: **partially resolved** — everyday causal-state tracking is handled inline by `refs_map_b64` (see [pq_dialogs.md §References](../../reqs/pq_dialogs.md)). This doc covers the remaining use case: standalone, portable, Merkle-rooted attestations for export and dispute resolution.

## What `refs_map_b64` already solves

Every dialog message carries an encrypted `refs_map_b64` — a `{message_id: sign_hash}` map of all DAG tails the sender observed at authoring time. This is effectively a **per-message inline snapshot** of the conversation frontier:

- **Catch-up** — a peer can walk `refs_map` chains transitively to reconstruct the full DAG without a separate snapshot artifact.
- **Causal state at any point** — each message records exactly what its author had seen, signed and tamper-evident.
- **Fork detection** — multiple tails in a refs_map surface concurrent sends; a merge is any message that references both fork tips.

For most operational needs (sync, ordering, state recovery), `refs_map_b64` is sufficient. No additional table or artifact is required.

## Remaining problem: portable attestations

`refs_map_b64` is encrypted and distributed across individual message rows. It does **not** serve use cases that require:

- **Archival / export** — a user wants a single, self-contained, authentic record of a conversation they can store outside the system or present to a third party.
- **Dispute resolution** — "this conversation included these messages at this point in time" as a signed artifact, not a claim that requires replaying and decrypting the full message log.
- **Cross-peer comparison** — two peers comparing their view of the conversation at the same logical time without exchanging all messages.

These require a **standalone snapshot** — a signed row that attests to the full reachable graph in one portable object.

## Approach (for standalone snapshots)

A **snapshot** is a signed row that references the full reachable graph of `(message_id, sign_hash)` pairs for a conversation as known to its author at snapshot time.

| Field | Role |
|---|---|
| `conversation_hash` | Scope (`dialog_hash` or future `room_hash`). |
| `author_hash` | Who took the snapshot. |
| `taken_at` | `owner_timestamp` at snapshot time. |
| `graph_root_hash` | Merkle root over the sorted list of `(message_id, sign_hash)` pairs. |
| `tip_ids` | List of tip `message_id`s (multiple if the conversation is forked). |
| `graph_payload` | The full `(message_id, sign_hash)` list. Always inlined — the snapshot is a self-contained artifact. |
| `sign_b64` | ML-DSA-87 over everything above. |

Verification of a snapshot:

1. Recompute `graph_root_hash` from `graph_payload`; compare.
2. Verify `sign_b64` with `author_hash`'s `sign_pkey` (fetched from [user_cards](./02_integrity.md)).
3. For any referenced message the verifier already holds, confirm its `sign_hash` matches the snapshot's entry — detects tampering on *either* side.

The snapshot is a peer's honest assertion about what it saw. It is not proof that those messages existed for *everyone* — but two peers' snapshots at the same `taken_at` should agree on their intersection.

## Relationship to `refs_map_b64`

| Aspect | `refs_map_b64` (inline) | Standalone snapshot |
|---|---|---|
| Scope | Frontier only (tails) | Full reachable graph |
| Granularity | Per-message | On-demand / periodic |
| Encrypted | Yes (only participants read) | Optionally — export may be plaintext graph |
| Portable | No (spread across rows) | Yes (single signed artifact) |
| Merkle proof | No | Yes (`graph_root_hash`) |
| Server-visible | No (opaque ciphertext) | Depends on storage choice |

A standalone snapshot can be **reconstructed** from the `refs_map_b64` chain by walking all messages and collecting the union of referenced pairs — but the snapshot compresses that into a single signed attestation with a Merkle root for efficient subset verification.

## Relationship to other problems

- **Built on**: `sign_hash` from [integrity](./02_integrity.md), `refs_map_b64` from [pq_dialogs.md](../../reqs/pq_dialogs.md).
- **Storage channel**: `graph_payload` is always inlined — the snapshot must be self-contained and portable without depending on external blob storage.
- **Not a consensus mechanism**: snapshots are per-author attestations, not a shared agreement. Two peers can produce divergent snapshots if they observed different tips; comparing them is how divergence is detected.

## Where this touches existing work

- **Existing mention**: [README](./README.md) — "snapshot of conversation state signed by peer [full graph of message_uuids and sign_hashes]".
- **Inline snapshots**: [pq_dialogs.md §References](../../reqs/pq_dialogs.md) — `refs_map_b64` provides per-message frontier snapshots that handle everyday catch-up and ordering.

## Invariants

- A snapshot's `graph_payload` must be complete for the conversation — partial snapshots are a different feature (range snapshots) and would be a new row type.
- `graph_root_hash` is deterministic: same set of `(message_id, sign_hash)` pairs, same root, independent of traversal order. Pairs are sorted by `message_id` before hashing.
- Snapshots are append-only — a peer may publish many over time; none are mutated.

## Open questions

- **Frequency / policy**: on-demand vs. periodic vs. pinned-by-UI. Since `refs_map_b64` handles operational needs, standalone snapshots are likely on-demand only (user-triggered export or dispute).
- **Encryption**: should `graph_payload` be encrypted (private attestation) or plaintext (verifiable by third parties without dialog keys)? Export and dispute resolution favor plaintext; privacy favors encrypted.
- **Partial snapshots**: "everything since `message_id = X`" — useful for large conversations, but doubles the verification logic.
- **Garbage collection**: once a snapshot exists, can messages older than the snapshot's full graph be pruned? The snapshot's Merkle root proves they existed even if the rows are gone.

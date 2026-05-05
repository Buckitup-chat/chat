# Ordering

## Problem

Dialog and room messages are authored concurrently by multiple peers and delivered over an eventually-consistent sync layer. The data layer must let any peer reconstruct a **total causal order** per conversation without a central sequencer, and must make it impossible for a peer to silently insert a message "between" two earlier ones after the fact.

This is distinct from [data versioning](./03_data_versioning.md): versioning orders revisions of a single key by a single author; ordering threads independent authors' messages into a shared timeline.

## Solution: `refs_map_b64` + UUIDv7

The dialog schema in [pq_dialogs.md](../../reqs/pq_dialogs.md) solves ordering with two mechanisms:

### 1. `refs_map_b64` — full DAG frontier (causality)

Every message carries an encrypted map of **all DAG tails** the sender observed at authoring time — a `{message_id: sign_hash}` map of every leaf in the sender's viewport.

- A single-predecessor chain is the degenerate case (one entry in the map).
- Concurrent sends (forks) are captured naturally — both fork tips appear in the next message's refs_map, merging the fork.
- The map pins both message identity *and* exact version (`sign_hash`), so edits are tracked in causal context.

The map is encrypted under `sender_msg_key` and covered by `sign_b64`, so reparenting is tamper-evident.

### 2. `message_id` = UUIDv7 (display order)

`message_id` embeds a timestamp, giving a natural display order without requiring DAG traversal. UUIDv7 ordering is advisory for display; the DAG formed by `refs_map_b64` is authoritative for causality.

### Server-visible causality trade-off

Causal validation is a frontend responsibility — the server sees only opaque ciphertext. The privacy gain (server cannot reconstruct conversation flow) outweighs the loss of server-side ingest enforcement.

## Invariants

- `refs_map_b64` is encrypted under `sender_msg_key`; only participants can decrypt and validate the causal graph.
- `sign_b64` covers `refs_map_b64` (the ciphertext blob), so any mutation breaks the signature.
- Genesis message: `refs_map` plaintext is `{}`. Only one message per dialog may have an empty refs_map; enforced by the frontend, not the database.
- Forks are allowed (two messages referencing the same tails) and surfaced to the UI; resolution is a rendering concern.
- Edits do **not** change the original `refs_map_b64` preserved in `dialog_messages_versions` — causal context is fixed at first authoring for each version. The tip's `refs_map_b64` may be recomputed on edit to reflect the sender's current viewport.
- `refs_map_b64` is orthogonal to `parent_sign_hash`: `parent_sign_hash` chains revisions of the same message by the same author; `refs_map_b64` captures cross-author causal context.

## Ingest rules (frontend-enforced)

1. **Tail resolution.** On decrypt, verify that every `message_id` in the refs_map resolves to a locally known message in the same `dialog_hash`. Missing references imply out-of-order delivery — queue the message until its refs resolve.
2. **Signature check.** Verify `sign_b64` under `sender_hash`'s `sign_pkey`. Covers `refs_map_b64` ciphertext, so post-hoc reparenting fails.
3. **Genesis uniqueness.** At most one message per `dialog_hash` should have an empty `refs_map`. A second empty-map message is a protocol violation; clients surface it as a fork at the root.
4. **No self-reference.** A message's own `(message_id, sign_hash)` must not appear in its `refs_map`.

## Remaining open questions

- **Conversation scope.** `refs_map_b64` is defined per `dialog_hash`; the same mechanism extends to rooms once `room_hash` lands in `pq_rooms.md`.
- **Catch-up protocol.** When a peer joins mid-conversation, all referenced messages must be backfillable. Likely a per-conversation Electric shape with `WHERE dialog_hash = ?` plus a bounded pending queue for messages whose refs haven't arrived.
- **Malicious stale references.** An author can deliberately reference old tails to fork the DAG even when fresher tips are visible. Detectable (the fork is explicit) but not preventable; rendering policy is a UI concern.
- **Garbage collection.** Pruning old messages breaks refs_map resolution for anything downstream. Retention story is owned by [08_snapshots.md](./08_snapshots.md); until then, assume append-only.

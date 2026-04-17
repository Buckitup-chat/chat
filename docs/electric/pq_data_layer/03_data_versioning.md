# Data Versioning

> Status: **solved for user storage** — `user_storage_versions` holds the full chain; `user_storage` holds the tip.

## Problem

Under multi-peer sync with last-write-wins, a single row cannot preserve authorship history: concurrent edits collapse, and a malicious peer can rewrite the past undetectably. The PQ data layer needs a hash-linked version chain so that any peer can reconstruct and verify the lineage of a value.

## Approach

Two tables per versioned entity — one for the current tip, one for the history.

| Field | Role |
|---|---|
| `sign_hash` | Identity of *this version* — hash of the row's signature. |
| `parent_sign_hash` | Points to the previous version's `sign_hash` (nullable for the first version). |
| `owner_timestamp` | Monotonic counter — defeats replay and tie-breaks concurrent branches. |
| `sign_b64` | ML-DSA-87 signature covering the row fields, including `parent_sign_hash`. |

Because `sign_b64` signs `parent_sign_hash`, the chain is tamper-evident: rewriting any historical version breaks all descendants' signatures. The tip (`user_storage`) always points into the history table via a foreign key on `parent_sign_hash`.

Encoding: `sign_hash` is an "uss_"-prefixed hex string for user-storage entities (see [pq_user_storage.md §7.3](../../reqs/pq_user_storage.md)).

## Where this lives

- **Tables**: `user_storage`, `user_storage_versions` — [SCHEMAS.md](./SCHEMAS.md)
- **Version semantics**: [SCHEMAS.md §Version History Model](./SCHEMAS.md)
- **Write path**: [pq_user_storage.md §5.2](../../reqs/pq_user_storage.md)
- **Ingestion model ownership**: [Electric_Abstraction_Layer.md](../Electric_Abstraction_Layer.md) (`UserStorage` has parent-existence checks)

## Invariants

- `user_storage_versions` is append-only — updates only add new rows, never mutate existing ones.
- `parent_sign_hash` is a foreign key into `user_storage_versions.sign_hash` (self-referential). A version cannot be inserted unless its parent is already known locally.
- `sign_hash` uniquely identifies a version across all peers — two peers producing the same `(user_hash, uuid, value_b64, parent_sign_hash, owner_timestamp)` would produce the same hash, but they would also need the same signature, which is impossible without the same `sign_skey` — so `sign_hash` is safely globally unique per author.
- Conflict resolution at the tip is LWW by `owner_timestamp`; the full history remains intact in `user_storage_versions` regardless of which branch "wins" at the tip.

## What it does not yet solve

- **Message ordering** across authors in a dialog — versioning models per-key lineage from a single author, not interleaved conversation state. See [04_ordering.md](./04_ordering.md).
- **Branching / reply threads** — the chain is linear per key. A fan-out graph would need a different structure. See [05_branching.md](./05_branching.md).
- **Cross-key snapshots** — versioning proves *this* key's history; a conversation-wide snapshot is a separate concern. See [08_snapshots.md](./08_snapshots.md).

## Open extensions

- Garbage collection policy for `user_storage_versions` (retention horizon, compaction).
- Peer-reconciliation UX when the same key has diverging branches under different parents.

# Data Versioning

> Status: **solved for user storage** — `user_storage_versions` holds the full chain; `user_storage` holds the tip.

## Problem

Under multi-peer sync with last-write-wins, a single row cannot preserve authorship history: concurrent edits collapse, and a malicious peer can rewrite the past undetectably. The PQ data layer needs a hash-linked version chain so that any peer can reconstruct and verify the lineage of a value.

## Approach

**Versioning is achieved by pairing two tables per versioned entity — a _master_ table holding the current (tip) version, and a _versions_ table holding every superseded version.** The canonical pair is `user_storage` (master) and `user_storage_versions` (history); every other versioned entity follows the same shape.

- **Master** (e.g. `user_storage`) — stores the latest version only. Carries `parent_sign_hash` pointing back into the versions table (NULL for a brand-new key with no history yet). On edit, the outgoing tip is appended to the versions table and the master row is rewritten in place with the new payload and a `parent_sign_hash` pointing at the just-archived row.
- **Versions** (e.g. `user_storage_versions`) — append-only history. Each row carries both `parent_sign_hash` (linking to its own predecessor) and `sign_hash` (its own identity, used as the FK target from descendants and from the next master-row archive step). Rows here are never mutated.

| Field | Where | Role |
|---|---|---|
| `sign_hash` | versions (required) + master (denormalized) | Identity of *this version* — hash of the row's signature. Required on versions rows where it is the FK target. The master row carries a denormalized copy for convenience: it is derivable from `sign_b64`, is not itself covered by the signature, and nothing FK-references it. Keeping it on the master avoids recomputing the hash both when archiving the outgoing tip into versions and when populating the next edit's `parent_sign_hash`. |
| `parent_sign_hash` | master + versions | Points to the previous version's `sign_hash` (nullable for the first version). |
| `owner_timestamp` | master + versions | Monotonic counter — defeats replay and tie-breaks concurrent branches. |
| `sign_b64` | master + versions | ML-DSA-87 signature covering the row fields, including `parent_sign_hash`. |

Because `sign_b64` signs `parent_sign_hash`, the chain is tamper-evident: rewriting any historical version breaks all descendants' signatures. The master row always points into the versions table via a foreign key on `parent_sign_hash`.

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

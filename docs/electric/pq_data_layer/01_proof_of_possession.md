# Proof-of-Possession

> Status: **solved** — middleware layer gates all `/electric/v1/ingest` writes.

## Problem

Every write to a PQ-replicated table must carry cryptographic proof that the client controls the sign key claimed in the row. Identity is a public key — without a proof-of-possession (PoP) check, any peer could forge rows under any `user_hash`.

## Approach

Client signs a short-lived, server-issued challenge with its `sign_skey` (ML-DSA-87) and submits `{challenge_id, signature}` alongside the mutation batch. Server:

1. Resolves `challenge_id` (1-minute TTL, single-use).
2. Looks up `sign_pkey` via the claimed `user_hash`.
3. Verifies the signature matches the challenge bytes.
4. Applies the batch inside a single transaction — one PoP covers the whole batch.

Challenges are fetched from `GET /api/v1/challenge` or reused from the previous `/api/v1/ingest` response. When a mutation requires both a user and a room key, the same challenge is signed twice and both signatures travel in the same `auth` block.

## Where this lives

- **Protocol spec**: [electric-proof-of-possesion.md](../../reqs/electric-proof-of-possesion.md)
- **User-side application of PoP**: [pq_user_storage.md §4.2](../../reqs/pq_user_storage.md)
- **Ingest controller**: `lib/chat_web/controllers/electric_controller.ex`
- **Abstraction layer context**: [Electric_Abstraction_Layer.md](../Electric_Abstraction_Layer.md) — PoP runs *before* per-model `authorize/2`

## Invariants

- Reads are public — no PoP needed.
- Peer-to-peer replication (`Electric.ShapeWriter`) **bypasses** PoP: sync is a trusted internal operation between already-verified rows (see [electric_network_sync.md](../../reqs/electric_network_sync.md)). Integrity is re-checked per-row from signatures.
- Challenge reuse across requests is disallowed — replay prevention.

## Open extensions

- Room-scoped challenges for group operations.
- Device-delegated PoP (hardware-backed signer).

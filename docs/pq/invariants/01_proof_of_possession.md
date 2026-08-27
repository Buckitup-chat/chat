# Proof-of-Possession

> Status: **solved** — middleware layer gates all `/electric/v1/ingest` writes.

## Problem

Every write to a PQ-replicated table must carry cryptographic proof that the client controls the sign key claimed in the row. Identity is a public key — without a proof-of-possession (PoP) check, any peer could forge rows under any `user_hash`.

## Approach

The challenge is a random string with a 1-minute TTL. Client signs it with its `sign_skey` (ML-DSA-87) and submits the proof in the request body as `auth.challenge_id` and `auth.signature` (base64-encoded). Server:

1. Resolves `challenge_id` (1-minute TTL, single-use).
2. Looks up `sign_pkey` via the claimed `user_hash`.
3. Verifies the signature matches the challenge bytes.
4. Applies the batch — one PoP covers the whole batch.

Challenges are fetched from `GET /electric/v1/challenge` or reused from the previous `/electric/v1/ingest` response.

The PoP context is resolved once per request and shared across all mutations in the batch, but "batch" means different things on the two ingest endpoints:

- `POST /electric/v1/ingest` applies every mutation inside one `Writer.apply` call — one shared transaction, all-or-nothing.
- `POST /electric/v1/ingest_each` applies each mutation via its own `Writer.apply` call (`ChatWeb.ElectricController.apply_single_mutation/2`) so callers get a per-mutation status — each mutation commits (or fails) in its own transaction, even though they all reuse the same single-use PoP challenge/signature.

## Where this lives

- **Protocol spec**: [electric-proof-of-possesion.md](../reqs/electric-proof-of-possesion.md)
- **User-side application of PoP**: [pq_user_storage.done.md §4.2](../reqs/pq_user_storage.done.md)
- **Ingest controller**: `lib/chat_web/controllers/electric_controller.ex` (`ingest/2` — batched; `ingest_each/2` — per-mutation transactions, same PoP context)
- **Abstraction layer context**: [Electric_Abstraction_Layer.md](../electric/Electric_Abstraction_Layer.md) — PoP runs *before* per-model `authorize/2`

## Invariants

- Reads are public — no PoP needed.
- Peer-to-peer replication (`Electric.ShapeWriter`) **bypasses** PoP: sync is a trusted internal operation between already-verified rows (see [electric_network_sync.md](../reqs/electric_network_sync.md)). Integrity is re-checked per-row from signatures.
- Challenge reuse across requests is disallowed — replay prevention.
- Not every replicated table is reachable through ingest: shapes that don't implement `ingest_configure_writer/2` (e.g. `ReviewPostRight`, `ReviewRevokeRight`) get no `Writer.allow` config, so `Phoenix.Sync.Writer` rejects any mutation targeting them outright rather than running a PoP check. Those rows are written server-side only (e.g. when a review's secret-sharing threshold resolves).

## Open extensions

- **Room-scoped challenges for group operations.** Not implemented: rooms aren't PQ/Electric-replicated entities yet (`pq_rooms.md` is TBD; rooms still sync over the legacy GraphQL/CubDB path per [electric_network_sync.md](../reqs/electric_network_sync.md)). The eventual design signs the same challenge twice — once per key the mutation depends on — with both signatures traveling in the same `auth` block, mirroring the current single-signature shape. No shape's `*_allowed` check and no client `auth` payload builder currently supports more than one signature.
- Device-delegated PoP (hardware-backed signer).

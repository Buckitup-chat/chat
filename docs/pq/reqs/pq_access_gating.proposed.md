# PQ API Access Gating

## Purpose

Control who can write data through the Electric ingest API. The system starts in `open` mode. The first user to ingest a `user_card` registers unconditionally and becomes the **owner** (persisted in AdminDB). While in `open` mode, anyone can ingest. When the owner switches to `trust` mode, all subsequent users are subject to vouch-chain evaluation. Shape reads remain open — all synced data is encrypted, so read access leaks nothing useful.

---

## Access Modes

| Mode | New user_card ingest | Other ingest (existing users) | Shape reads |
|------|---------------------|-------------------------------|-------------|
| `open` | Anyone | Anyone with valid PoP | Open |
| `trust` | Auto-approved if within chain distance | Chain-gated (see [Trust Gate](#trust-gate)) | Open |

Default mode: `open` (preserves current behavior).

Optical-handshake contacts and explicit owner approvals are vouch tokens with different scopes — they place a user at chain distance 1 from the owner. The owner controls effective behavior by tuning the maximum allowed chain depth.

---

## Bootstrap and Owner

The system starts in `open` mode with no owner. The first `user_card` successfully ingested registers that user as the **owner** — their `user_hash` and `sign_pkey` are persisted in AdminDB. The mode remains `open` until the owner explicitly switches to `trust`.

- Owner is always approved regardless of mode.
- Owner can change the access mode (`open` ↔ `trust`).
- Owner can explicitly approve or revoke any `user_hash` (issues/tombstones a vouch token).
- Owner can set the maximum chain depth.
- There is exactly one owner. Ownership transfer is out of scope for this requirement.

---

## Contacts as Trust Signal

The owner's trusted contacts (established via the [optical handshake flow](../flows/pq_optical-handshake.livemd)) are vouch tokens that place a user at chain distance 1.

### Flow

1. Owner performs optical handshake with a peer — exchanging ECC public keys and proving key ownership via signed nonces.
2. Owner's device stores the peer's `user_hash` + `ecc_pub` as a ContactCandidate.
3. When the peer's UserCard appears (via shape sync), the candidate is verified (matching `user_hash` and `contact_pkey`) and promoted to a trusted Contact.
4. A vouch token with scope `origins.<origin_hash>.identity.optical-handshake` is issued for the contact's `user_hash`.

### Implications

- Contact trust is directional — the *owner's* contacts receive a vouch, not every user's contacts.
- Revoking a contact revokes the vouch token (signed tombstone), which breaks the chain at that edge.
- Setting max depth to **1** achieves "contacts-only" behavior — only users with a direct vouch from the owner pass.

---

## Trust Gate

In `trust` mode, access decisions are driven by **chain distance** — the shortest path in the vouch token graph from the owner to the user. The owner sets a maximum depth; users reachable within that depth can ingest, users beyond it (or unreachable) are rejected.

The chain distance is computed by the recursive CTE defined in [Vouch Tokens § Graph Traversal](pq_vouch_tokens.proposed.md#graph-traversal-via-recursive-cte). That query walks `issuer_hash → subject_hash` edges, filters by scope prefix and `deleted_flag`, and returns `MIN(distance)` per user.

### Max Depth

The owner sets a maximum chain depth (integer, ≥ 1) via the admin UI. Default: **3**.

- Users with `chain_distance ≤ max_depth` can ingest.
- Users beyond max depth or with no path are rejected with `403` and body `{"error": "not_in_trust_chain", "max_depth": <max_depth>}`.
- The owner can override: explicitly approve a user regardless of distance (issues a direct vouch), or explicitly revoke a user regardless of distance (tombstones their vouches).

### Vouch Scope Meanings

All approval mechanisms are vouch tokens with different scopes (see [Vouch Tokens § Relationship to Access Gating](pq_vouch_tokens.proposed.md#relationship-to-access-gating)):

| Mechanism | Vouch scope | Chain distance effect |
|-----------|-------------|----------------------|
| Optical handshake | `origins.<origin_hash>.identity.optical-handshake` | 1 (direct from owner) |
| Manual owner approval | `origins.<origin_hash>.identity.manual-approval` | 1 (direct from owner) |
| User-to-user vouch | `origins.<origin_hash>.vouch.direct` | +1 from voucher |
| Transitive (chain walk) | `origins.<origin_hash>.vouch.transitive` | Computed by CTE |

### Recomputation

The [resolved chain cache](pq_vouch_tokens.proposed.md#optimization--resolved-chain-cache) stores distance results for up to 30 minutes. Cache invalidation happens on vouch insert/revoke within the origin prefix.

---

## Approval List

A persistent set of approved users with their signing public keys:

| Field | Type | Notes |
|-------|------|-------|
| `user_hash` | text | Primary key, `"u_" + hex(SHA3-512(sign_pkey))` |
| `sign_pkey` | binary | ML-DSA-87 public key — the gate verifies PoP signatures directly against this |
| `source` | enum | `owner` / `optical_handshake` / `manual` / `vouch` |
| `approved_at` | integer | Unix timestamp |
| `revoked` | boolean | Soft revoke; `false` by default |

Storage: derived from [vouch tokens](pq_vouch_tokens.proposed.md) (PostgreSQL, synced via Electric). Owner identity and mode setting live in AdminDB — see [Open Questions §3](#open-questions).

Storing `sign_pkey` lets the gate verify the PoP signature against the approved key *before* the ingest reaches the writer — no DB lookup needed. It also means the gate can authenticate requests for any table, not just `user_card` mutations that carry a `user_hash` field.

---

## Gating Mechanics

### Where

A new plug `ChatWeb.Plugs.ElectricAccessGate` in the router, applied to the ingest scope (after `ElectricReadiness`, before `ElectricChallengeInjector`):

```
scope "/" do
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricAccessGate   # <-- new

  scope "/" do
    pipe_through ChatWeb.Plugs.ElectricChallengeInjector
    post "/ingest", ElectricController, :ingest
    post "/ingest_each", ElectricController, :ingest_each
  end
end
```

### What it checks

1. **No owner registered yet** → allow the ingest. If this is a `user_card` insert, register the user as owner in AdminDB (post-ingest hook or writer callback). Mode stays `open`.
2. **Mode is `open`** → pass through (current behavior).
3. **Request's `user_hash` is the owner** → pass through.
4. **Mode is `trust`** → look up chain distance for `user_hash` (from cache or CTE); if `chain_distance ≤ max_depth`, pass through; if beyond or no path, reject with `403`.
5. **Otherwise** → reject with `403 Forbidden`, body: `{"error": "access_denied", "mode": "<current_mode>"}`.

### Identifying the caller

The ingest request carries a PoP signature (signed challenge). The gate uses the approval list's `sign_pkey` entries to verify who is calling:

1. Extract the challenge + signature from `params["auth"]`.
2. Iterate approved (non-revoked) entries and attempt `ML-DSA-87.verify(challenge, signature, entry.sign_pkey)`.
3. A match identifies the caller and confirms they are approved — proceed.
4. No match among approved entries — check if this is a `user_card` create mutation. If so, extract `sign_pkey` from the mutation payload, compute `user_hash`, and verify the signature against that key. If valid: in `open` mode, allow; in `trust` mode, check chain distance.

This avoids needing any PostgreSQL lookup — the approval list (derived from vouch tokens) is the sole authority.

---

## Server / Bot Access

Servers and bots that ingest data are identified by their `user_hash` the same way human users are. They must be approved through the same mechanism — either as an owner contact or via explicit manual approval.

No separate "API key" or "server token" concept. The PQ PoP flow is the universal auth.

---

## Owner UI

### Minimum viable

An admin endpoint or LiveView page where the owner can:

1. See the current access mode (`open` / `trust`).
2. Switch between modes.
3. Set the maximum chain depth (when in `trust` mode).
4. See users with their chain distance and vouch path.
5. Manually approve a `user_hash` (issues a manual-approval vouch token).
6. Revoke a user (tombstones their vouch tokens).

### Location

Under the existing Electric sandbox area (`/electric/admin`) or a new route. Gated by owner PoP — only the owner's identity can access it.

---

## Challenge / Ingest Flow with Gating

```
Client                          Server
  |                                |
  |-- GET /challenge ------------->|  (unchanged)
  |<-- {challenge_id, challenge} --|
  |                                |
  |-- POST /ingest --------------->|
  |   {auth: {challenge_id, sig}, |
  |    mutations: [...]}           |
  |                                |
  |   [ElectricReadiness]          |  DB + Electric up?
  |   [ElectricAccessGate]         |  Mode check:
  |     - no owner? pass + claim   |    - no owner → pass, register as owner in AdminDB
  |     - open? pass               |    - open → pass
  |     - owner? pass              |    - owner → always pass
  |     - trust? chain check       |    - trust mode → chain_distance ≤ max_depth → pass
  |     - else? 403                |    - else → 403
  |   [ChallengeInjector]          |
  |   [ElectricController.ingest]  |  PoP verify + writer
  |                                |
  |<-- {txid} or error ------------|
```

---

## Status

Proposed.

## Open Questions

1. Should the owner be able to delegate approval rights to other approved users?
2. Should there be a "pending" state where unapproved users' requests are queued rather than rejected?
3. **Where to store owner identity and mode setting?**

   Owner `user_hash` + `sign_pkey`, access mode, and max chain depth live in AdminDB (CubDB). The approval list itself is derived from vouch tokens (see [Vouch Tokens](pq_vouch_tokens.proposed.md)), which sync as an Electric shape and are stored in PostgreSQL.

   Sub-question: should AdminDB settings be **replicated to the backup drive**? On the platform, each USB drive gets its own PG instance with logical replication between main and internal. AdminDB is currently single-drive — backup requires explicit copy logic.

4. **Should chain distance be visible to users?** Transparency aids debugging ("why was I rejected?") but also reveals the trust topology. Options: visible to owner only, visible to each user for their own distance, or fully opaque.

5. **Offline chain evaluation.** Should vouch attestations be structured as self-contained signed tokens so the gate can evaluate trust without any live lookups — just the token chain? This would allow chain-distance computation even when disconnected from the trust authority.

6. **Should a future version add composite scoring?** Chain distance is sufficient as a starting point, but richer signals (vouch quality, behavioral patterns, tenure) could be layered in later if the simple model proves too coarse. Keeping this as a known extension point.

---

## References

- [Vouch Tokens](pq_vouch_tokens.proposed.md) — schema, graph traversal CTE, scope attenuation, cache
- [Optical Handshake Flow](../flows/pq_optical-handshake.livemd) — contact establishment via physical proximity

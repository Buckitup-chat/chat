# PQ API Access Gating

## Purpose

Control who can read and write data through the Electric API. Three distinct surfaces are gated:

- **Write (ingest)** — vouch-chain + PoP, controlled by access mode (`open` / `guarded` / `trust`).
- **Read / sync (shape subscriptions)** — PoP-gated; additionally chain-gated in `trust` mode.
- **Network discovery** — captures the peer's sync key so clients can establish sync relationships.

The system starts in `open` mode. The first user to ingest a `user_card` registers unconditionally and becomes the **owner** (persisted in AdminDB). While in `open` mode, anyone with valid PoP can read and write. The owner can escalate to `guarded` (writes chain-gated, reads open) or `trust` (all access chain-gated). The server provides nothing to clients unless they ask — a client must know the device serial number to request access.

---

## Access Modes
| Mode | New user_card ingest | Other ingest (existing users) | Shape reads / sync |
|------|---------------------|-------------------------------|--------------------|
| `open` | Anyone | Anyone with valid PoP | Anyone with valid PoP |
| `guarded` | Allowed if within chain distance | Chain-gated (see [Trust Gate](#trust-gate)) | Anyone with valid PoP |
| `trust` | Allowed if within chain distance | Chain-gated (see [Trust Gate](#trust-gate)) | Chain-gated (same mechanism) |

Default mode: `open` (preserves current behavior). `guarded` mode gates writes via vouch chain but leaves reads open to anyone with valid PoP. `trust` mode gates **all** access — reads, writes, and peer sync — via PoP + vouch chain. The same mechanism applies to users and peer servers alike.

> **New user_cards in gated modes:** In `guarded` and `trust` modes, a new `user_card` ingest is allowed through when the user's `user_hash` already has a vouch token chain path within `max_depth` — e.g., the owner issued a vouch via optical handshake or manual approval before the user submitted their card. The vouch edge exists first; the card ingest passes the gate because the user is already reachable.

Optical-handshake contacts and explicit owner approvals are vouch tokens granting `device.<sn>.storage.write` (and optionally `device.<sn>.storage.read`) — they place a user at chain distance 1 from the owner. Provenance (how trust was established) is inferred from the issuer, not encoded in the scope. The owner controls effective behavior by tuning the maximum allowed chain depth.

---

## Bootstrap and Owner

The system starts in `open` mode with no owner. The first `user_card` successfully ingested registers that user as the **owner** — their `user_hash` and `sign_pkey` are persisted in AdminDB. The mode remains `open` until the owner explicitly changes it.

- Owner is always approved regardless of mode.
- Owner can change the access mode (`open` ↔ `guarded` ↔ `trust`).
- Owner can explicitly approve or revoke any `user_hash` (issues/tombstones a vouch token).
- Owner can set the maximum chain depth.
- There is exactly one owner. Ownership transfer is out of scope for this requirement.

---

## Server Identity Key

Every participant — user or server — has its own keypair and authenticates the same way. A user reads the shapes endpoint the same way a peer server does: present your key, prove possession, get checked against the vouch chain (when trust mode is enabled).

### Server Key Lifecycle

1. **Generation**: On first start (before any owner is registered), the device generates a keypair and persists it in AdminDB.
2. **Storage**: AdminDB (CubDB) only. Not replicated via Electric — it gates Electric access itself.
3. **Identity**: The server's `user_hash` is derived from its public key, same formula as user identities: `"u_" + hex(SHA3-512(sign_pkey))`.

### Network Discovery

The server provides nothing unless the client asks — a client must know the device serial number. **Network discovery** captures the peer server's public key so that:

- A client can authenticate the server it syncs from.
- A peer server can authenticate against the target device's gate.

The exact discovery protocol (mDNS, optical handshake extension, manual entry) is defined by the discovery flow, not this requirement.

### Peer-to-Peer Sync

When device A syncs from device B, device A acts as a client — it authenticates to B using its own server key via PoP, and B checks A against the vouch chain (in `trust` mode). The mechanism is identical to a user reading shapes: same plug, same check, same vouch token scopes.

---

## Contacts as Trust Signal

The owner's trusted contacts (established via the [optical handshake flow](../flows/pq_optical-handshake.livemd)) are vouch tokens that place a user at chain distance 1. **Creating these vouch tokens is a frontend responsibility** — after a successful handshake, the frontend issues the vouch token on the owner's behalf.

> The optical handshake flow itself (candidate storage, verification, promotion) is defined in [Optical Handshake Flow](../flows/pq_optical-handshake.livemd) and is out of scope for this requirement.

### Implications

- Contact trust is directional — the *owner's* contacts receive a vouch, not every user's contacts.
- Revoking a contact revokes the vouch token (signed tombstone), which breaks the chain at that edge.
- Setting max depth to **1** achieves "contacts-only" behavior — only users with a direct vouch from the owner pass.

---

## Trust Gate

In `guarded` and `trust` modes, access decisions are driven by **chain distance** — the shortest path in the vouch token graph from the owner to the user. The owner sets a maximum depth; users reachable within that depth can ingest, users beyond it (or unreachable) are rejected.

The chain distance is computed by the recursive CTE defined in [Vouch Tokens § Graph Traversal](pq_vouch_tokens.proposed.md#graph-traversal-via-recursive-cte). That query walks `issuer_hash → subject_hash` edges, filters by resource scope prefix (e.g. `device.<sn>.storage.write` or `device.<sn>.storage.read`) and `deleted_flag`, and returns `MIN(distance)` per user.

### Max Depth

The owner sets a maximum chain depth (integer, ≥ 1) via the admin UI. Default: **3**.

- Users with `chain_distance ≤ max_depth` can ingest.
- Users beyond max depth or with no path are rejected with `403` and body `{"error": "not_in_trust_chain", "max_depth": <max_depth>}`.
- The owner can override: explicitly approve a user regardless of distance (issues a direct vouch), or explicitly revoke a user regardless of distance (tombstones their vouches).

### Resource Scopes

Resource kinds separate read and write access. The scope names the facility being granted, not how trust was established (see [Vouch Tokens § Resource Forest](pq_vouch_tokens.proposed.md#resource-forest)):

| Mechanism | Issuer | Vouch `kind` | Chain distance |
|-----------|--------|--------------|----------------|
| Optical handshake | owner | `device.<sn>.storage.write` + `device.<sn>.storage.read` | 1 |
| Manual owner approval | owner | configurable: `storage.write`, `storage.read`, or both | 1 |
| User-to-user vouch | non-owner user | attenuated from voucher's own scope | +1 from voucher |

A vouch for `device.<sn>.storage.write` grants ingest (all shapes); `device.<sn>.storage.write.<shape>` narrows to a single shape. Likewise `device.<sn>.storage.read` grants shape subscription / sync, narrowable per shape. The `guarded` mode enforces only `storage.write` scopes; `trust` mode enforces both `storage.write` and `storage.read`.

Provenance is inferred: `issuer_hash` = owner → direct trust; `issuer_hash` ≠ owner → transitive vouch. The mechanism (optical handshake vs. manual approval) is indistinguishable at the token level — both are owner-issued vouches for the same resource.

### Recomputation

The [resolved chain cache](pq_vouch_tokens.proposed.md#optimization--resolved-chain-cache) stores distance results for up to 30 minutes. Cache invalidation happens on vouch insert/revoke within the resource scope prefix.

---
## Caller Resolution (no separate approval list)

A dedicated approval list table is unnecessary — the gate resolves callers from existing data:

1. **`user_cards`** (Electric-synced) provide `sign_pkey` for each `user_hash`.
2. **Vouch tokens** (Electric-synced) provide chain distance via the [resolved chain cache](pq_vouch_tokens.proposed.md#optimization--resolved-chain-cache).

The gate identifies the caller by `user_hash` (provided in the auth payload), looks up `sign_pkey` from `user_cards`, verifies the PoP signature, then checks chain distance from the cache. No derived table needed.

Owner identity and mode setting live in AdminDB — see [Open Questions §3](#open-questions).

---

## Gating Mechanics

### Where

A single plug `ChatWeb.Plugs.ElectricAccessGate` gates all access — reads, writes, and peer sync — using the same PoP + vouch chain mechanism:

```
scope "/" do
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricAccessGate   # <-- new: PoP + vouch chain for all access

  get "/shape/*table", ElectricController, :shape

  scope "/" do
    pipe_through ChatWeb.Plugs.ElectricChallengeInjector
    post "/ingest", ElectricController, :ingest
    post "/ingest_each", ElectricController, :ingest_each
  end
end
```

### What it checks

The same logic applies to reads (shape subscriptions) and writes (ingest), and to both users and peer servers:

1. **No owner registered yet** → allow. If this is a `user_card` insert, register the user as owner in AdminDB (post-ingest hook or writer callback). Mode stays `open`.
2. **Mode is `open`** → verify PoP (caller must prove key ownership), then pass through.
3. **Caller is the owner** → pass through.
4. **Mode is `guarded`** → verify PoP. For **writes**: look up chain distance for caller's `user_hash` (from cache or CTE); if `chain_distance ≤ max_depth`, pass through; if beyond or no path, reject with `403`. For **reads**: PoP valid → pass through.
5. **Mode is `trust`** → verify PoP, then look up chain distance for caller's `user_hash` (from cache or CTE); if `chain_distance ≤ max_depth`, pass through; if beyond or no path, reject with `403`. Applies to both reads and writes.
6. **Otherwise** → reject with `403 Forbidden`, body: `{"error": "access_denied", "mode": "<current_mode>"}`.

### Identifying the caller

The request carries a PoP signature (signed challenge) and the caller's `user_hash`:

1. Extract `user_hash`, `challenge_id`, and `signature` from `params["auth"]`.
2. Look up `sign_pkey` from `user_cards` for the given `user_hash`.
3. Verify `ML-DSA-87.verify(challenge, signature, sign_pkey)`. If valid → caller is identified, proceed with mode checks.
4. If `user_hash` is unknown (no user_card yet) — check if this is a `user_card` create mutation. If so, extract `sign_pkey` from the mutation payload, compute `user_hash`, and verify the signature against that key. If valid: in `open` mode, allow; in `guarded`/`trust` mode, check chain distance.

Caller resolution uses `user_cards` + vouch token cache — no separate derived table needed.

---

## Server / Bot / Peer Access

Servers, bots, and peer devices are identified by their `user_hash` the same way human users are. A peer server's identity key (see [Server Identity Key](#server-identity-key)) produces a `user_hash` via the same formula. They must be approved through the same mechanism — either as an owner contact or via explicit manual approval.

No separate "API key" or "server token" concept. The PQ PoP flow is the universal auth for users, bots, and peer servers alike.

---

## Owner UI

### Minimum viable

An admin endpoint or LiveView page where the owner can:

1. See the current access mode (`open` / `guarded` / `trust`).
2. Switch between modes.
3. Set the maximum chain depth (when in `trust` mode).
4. See users with their chain distance and vouch path.
5. Manually approve a `user_hash` (issues `device.<sn>.storage.write` and/or `device.<sn>.storage.read` vouch tokens).
6. Revoke a user (tombstones their vouch tokens).

### Location

Under the existing Electric sandbox area (`/electric/admin`) or a new route. Gated by owner PoP — only the owner's identity can access it.

---

## Request Flows with Gating

Client below is a user device or a peer server — both authenticate the same way.

```
Client                          Server
  |                                |
  |  --- shape read (sync) --------
  |                                |
  |-- GET /shape/table ----------->|
  |   {auth: {challenge_id, sig}} |
  |                                |
  |   [ElectricReadiness]          |  DB + Electric up?
  |   [ElectricAccessGate]         |  PoP verify + mode check:
  |     - no owner? pass           |    (same logic as writes,
  |     - open? PoP ok → pass      |     except guarded skips
  |     - guarded? PoP ok → pass   |     chain check for reads)
  |     - owner? pass              |
  |     - trust? chain check       |
  |     - else? 403                |
  |   [ElectricController.shape]   |  SSE stream begins
  |                                |
  |<-- SSE: shape data ------------|
  |                                |
  |  --- write (ingest) -----------
  |                                |
  |-- GET /challenge ------------->|  (unchanged)
  |<-- {challenge_id, challenge} --|
  |                                |
  |-- POST /ingest --------------->|
  |   {auth: {challenge_id, sig}, |
  |    mutations: [...]}           |
  |                                |
  |   [ElectricReadiness]          |  DB + Electric up?
  |   [ElectricAccessGate]         |  PoP verify + mode check:
  |     - no owner? pass + claim   |    - no owner → pass, register as owner in AdminDB
  |     - open? PoP ok → pass      |    - open → PoP valid → pass
  |     - owner? pass              |    - owner → always pass
  |     - guarded? chain check     |    - guarded → chain_distance ≤ max_depth → pass (writes)
  |     - trust? chain check       |    - trust → chain_distance ≤ max_depth → pass (all)
  |     - else? 403                |    - else → 403
  |   [ChallengeInjector]          |
  |   [ElectricController.ingest]  |  writer
  |                                |
  |<-- {txid} or error ------------|
```

---

## Status

Proposed.

## Open Questions

1. **Should the owner be able to delegate vouching rights?** An approved user with `device.<sn>.storage.write` can already vouch for others (that's the transitive chain). The question is whether there should be a narrower scope that grants ingest but not the ability to vouch further.
2. ~~Should there be a "pending" state where unapproved users' requests are queued rather than rejected?~~ **Out of scope** — deferred to a separate feature.
3. **Where to store owner identity and mode setting?**

   Owner `user_hash` + `sign_pkey`, access mode, and max chain depth live in AdminDB (CubDB). Vouch tokens sync as an Electric shape and are stored in PostgreSQL; caller resolution uses `user_cards` + vouch token cache directly (no separate derived table).

   Sub-question: should AdminDB settings be **replicated to the backup drive**? On the platform, each USB drive gets its own PG instance with logical replication between main and internal. AdminDB is currently single-drive — backup requires explicit copy logic.

4. **Should chain distance be visible to users?** Transparency aids debugging ("why was I rejected?") but also reveals the trust topology. Options: visible to owner only, visible to each user for their own distance, or fully opaque.

5. **Offline chain evaluation.** ~~Should vouch attestations be structured as self-contained signed tokens?~~ **Yes** — vouch tokens must be self-contained signed attestations so the gate can evaluate trust without live lookups. Chain-distance computation works from the token chain alone, enabling offline evaluation. See [Vouch Tokens](pq_vouch_tokens.proposed.md) for the self-contained token structure.

6. **Should a future version add composite scoring?** Chain distance is sufficient as a starting point, but richer signals (vouch quality, behavioral patterns, tenure) could be layered in later if the simple model proves too coarse. Keeping this as a known extension point.

7. **Mutual authentication (future).** Currently the client authenticates to the server (PoP + sync key). A future extension could have the server prove its identity to the client — the client verifies it is syncing with the real `device.<sn>`, not a rogue server. This matters on LANs where DNS/mDNS spoofing is trivial. Possible approaches: server presents a signed challenge using a device identity key, or the sync key exchange during discovery is upgraded to a mutual key-agreement protocol.

---

## References

- [Vouch Tokens](pq_vouch_tokens.proposed.md) — schema, graph traversal CTE, scope attenuation, cache
- [Optical Handshake Flow](../flows/pq_optical-handshake.livemd) — contact establishment via physical proximity

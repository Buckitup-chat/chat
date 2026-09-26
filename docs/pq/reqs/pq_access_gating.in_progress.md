# PQ API Access Gating

## Purpose

Control who can read and write data through the Electric API. Three distinct surfaces are gated:

- **Write (ingest)** — vouch-chain + PoP, controlled by access mode (`open` / `guarded` / `trust`).
- **Read / sync (shape subscriptions)** — gated in `trust` mode only: a per-shape [read session](#read-gating-read-sessions) (PoP + chain check on open), then a Bearer token on every read.
- **Network discovery** — captures the peer's sync key so clients can establish sync relationships.

The system starts in `open` mode. The first user to ingest a `user_card` registers unconditionally and becomes the **owner** (persisted in AdminDB). While in `open` mode, anyone with valid PoP can read and write. The owner can escalate to `guarded` (writes chain-gated, reads open) or `trust` (all access chain-gated). The server provides nothing to clients unless they ask — a client must know the device serial number to request access.

---

## Access Modes
| Mode | `user_card` / `vouch_token` ingest | Other ingest | Shape reads / sync |
|------|------------------------------------|--------------|--------------------|
| `open` | Anyone with valid PoP | Anyone with valid PoP | Anyone (not gated) |
| `guarded` | Anyone with valid PoP (never chain-gated) | Chain-gated (see [Trust Gate](#trust-gate)) | Anyone (not gated) |
| `trust` | Anyone with valid PoP (never chain-gated) | Chain-gated (see [Trust Gate](#trust-gate)) | Read session + chain-gated (see [Read Gating](#read-gating-read-sessions)) |

Default mode: `open` (preserves current behavior). `guarded` mode gates writes via vouch chain and leaves reads open. `trust` mode gates **all** access — reads, writes, and peer sync — via PoP + vouch chain. The same mechanism applies to users and peer servers alike.

> **`user_card` and `vouch_token` are never chain-gated.** They are the inputs to chain resolution: `user_cards` supply `sign_pkey` for each `user_hash`, and vouch tokens are the graph edges. The server must accept every one it is offered, in any mode, so it can resolve chains. Gating them would be circular — a user couldn't become reachable without first being reachable, and a missing intermediate card or token would break chains for everyone downstream of it. Both still go through their shape's own PoP / signature checks. Accepting a card or token grants nothing by itself: the chain check on other shapes decides what the user can write.

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

When device A syncs from device B, device A acts as a client — it opens a [read session](#read-gating-read-sessions) on B with its own server key via PoP, and B checks A against the vouch chain (in `trust` mode). The mechanism is identical to a user reading shapes: same read gate, same check, same vouch token scopes.

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

The chain distance is computed by the recursive CTE defined in [Vouch Tokens § Graph Traversal](pq_vouch_tokens.in_progress.md#graph-traversal-via-recursive-cte). That query walks `issuer_hash → subject_hash` edges with bidirectional scope matching (a vouch at a wider scope covers narrower queries and vice versa), filters by `deleted_flag` with tombstone sub-selects, and returns `MIN(distance)` for the target user.

### Max Depth

The owner sets a maximum chain depth (integer, ≥ 1) via the admin UI. Default: **7**.

- Users with `chain_distance ≤ max_depth` can ingest.
- Users beyond max depth or with no path are rejected with `403` and body `{"error": "not_in_trust_chain", "max_depth": <max_depth>}`.
- The owner can override: explicitly approve a user regardless of distance (issues a direct vouch), or explicitly revoke a user regardless of distance (tombstones their vouches).

### Resource Scopes

Resource kinds separate read and write access. The scope names the facility being granted, not how trust was established (see [Vouch Tokens § Resource Forest](pq_vouch_tokens.in_progress.md#resource-forest)):

| Mechanism | Issuer | Vouch `kind` | Chain distance |
|-----------|--------|--------------|----------------|
| Optical handshake | owner | `device.<sn>.storage.write` + `device.<sn>.storage.read` | 1 |
| Manual owner approval | owner | configurable: `storage.write`, `storage.read`, or both | 1 |
| User-to-user vouch | non-owner user | attenuated from voucher's own scope | +1 from voucher |

A vouch for `device.<sn>.storage.write` grants ingest (all shapes); `device.<sn>.storage.write.<shape>` narrows to a single shape. Likewise `device.<sn>.storage.read` grants shape subscription / sync, narrowable per shape (`device.<sn>.storage.read.<shape>`, see [Read Gating](#read-gating-read-sessions)). The `guarded` mode enforces only `storage.write` scopes; `trust` mode enforces both `storage.write` and `storage.read`.

Provenance is inferred: `issuer_hash` = owner → direct trust; `issuer_hash` ≠ owner → transitive vouch. The mechanism (optical handshake vs. manual approval) is indistinguishable at the token level — both are owner-issued vouches for the same resource.

### Recomputation

The [resolved chain cache](pq_vouch_tokens.in_progress.md#optimization--resolved-chain-cache) stores distance results for up to 30 minutes. Cache invalidation happens on vouch insert/revoke within the resource scope prefix.

---
## Caller Resolution (no separate approval list)

A dedicated approval list table is unnecessary — the gate resolves callers from existing data:

1. **`user_cards`** (Electric-synced) provide `sign_pkey` for each `user_hash`.
2. **Vouch tokens** (Electric-synced) provide chain distance via the [resolved chain cache](pq_vouch_tokens.in_progress.md#optimization--resolved-chain-cache).

The gate identifies the caller by `user_hash` (provided in the auth payload), looks up `sign_pkey` from `user_cards`, verifies the PoP signature, then checks chain distance from the cache. No derived table needed.

Owner identity and mode setting live in AdminDB — see [Open Questions §3](#open-questions).

---

## Gating Mechanics

### Where

Writes and reads are gated by two plugs. They share the owner / mode / chain-distance decision but identify the caller differently:

- **Writes** — `ChatWeb.Plugs.ElectricAccessGate` (target; today `Chat.Pq.WriteGate`, see below). The caller proves possession with a one-time signed challenge in the request body.
- **Reads** — `ChatWeb.Plugs.ElectricReadGate`. The caller presents a Bearer token from a read session. See [Read Gating](#read-gating-read-sessions).

```
scope "/" do
  pipe_through ChatWeb.Plugs.ElectricReadiness

  scope "/" do
    pipe_through ChatWeb.Plugs.ElectricAccessGate   # <-- target: PoP + vouch chain for writes
    pipe_through ChatWeb.Plugs.ElectricChallengeInjector
    post "/ingest", ElectricController, :ingest
    post "/ingest_each", ElectricController, :ingest_each
  end
end

scope "/electric/v1/shapes" do
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricTableGuard
  pipe_through ChatWeb.Plugs.ElectricReadGate       # <-- new: Bearer read session + vouch chain
  forward "/", ChatWeb.Plugs.HexToBase64Electric
end
```

### What it checks (writes)

1. **No owner registered yet** → allow. If this is a `user_card` insert, register the user as owner in AdminDB (post-ingest hook or writer callback). Mode stays `open`.
2. **Mode is `open`** → verify PoP (caller must prove key ownership), then pass through.
3. **Caller is the owner** → pass through.
4. **Mode is `guarded` or `trust`** → verify PoP, then look up chain distance for caller's `user_hash`; if `chain_distance ≤ max_depth`, pass through; if beyond or no path, reject with `403`.
5. **Otherwise** → reject with `403 Forbidden`, body: `{"error": "access_denied", "mode": "<current_mode>"}`.

Reads follow [Read Gating § What the gate checks](#what-the-gate-checks).

### Identifying the caller (writes)

The request carries a PoP signature (signed challenge) and the caller's `user_hash`:

1. Extract `user_hash`, `challenge_id`, and `signature` from `params["auth"]`.
2. Look up `sign_pkey` from `user_cards` for the given `user_hash`.
3. Verify `ML-DSA-87.verify(challenge, signature, sign_pkey)`. If valid → caller is identified, proceed with mode checks.
4. If `user_hash` is unknown (no user_card yet) — check if this is a `user_card` create mutation. If so, extract `sign_pkey` from the mutation payload, compute `user_hash`, and verify the signature against that key. If valid, allow in every mode — `user_card` is never chain-gated (see the note under [Access Modes](#access-modes)).

Caller resolution uses `user_cards` + vouch token cache — no separate derived table needed.

### Current implementation: `Chat.Pq.WriteGate`

Until the `ElectricAccessGate` plug lands, write gating is enforced per shape, inside the ingest writer, not in the router pipeline. `Chat.Pq.WriteGate.and_gate/3` wraps a shape's `check` callback. The chain check runs only after the shape's own PoP/ownership check returns `:ok`:

```elixir
check:
  WriteGate.and_gate(&Validation.message_allowed(&1, user_pop_context), :dialog_messages,
    owner: "sender_hash"
  )
```

Decision order (`WriteGate.check_access/2`):

1. `:pq_gate_mode` is `:open` (or unset) → allow.
2. The owner field on the mutation is `nil` → allow.
3. No owner registered (`OwnerBootstrap.owner/0` is `nil`) → allow.
4. Caller is the owner → allow.
5. Otherwise, `VouchToken.chain_distance(owner_hash, user_hash, "device.<id>.storage.write.<shape>")` must return `{:ok, _}`. If it doesn't, the mutation is rejected with `{:error, "not_in_trust_chain"}`.

The caller's `user_hash` comes from `changes[field]` on insert and `data[field]` on update/delete. `field` defaults to `"user_hash"` and is overridden with `owner:` per shape:

| Shape | Owner field |
|-------|-------------|
| `dialog_keys`, `dialog_messages` | `sender_hash` |
| `dialog_message_reactions` | `reactor_hash` |
| `dialog_message_receipts` | `peer_hash` |
| `file`, `file_chunk` | `uploader_hash` |
| `origin`, `review_public_passwords` | `origin_hash` |
| `review`, `review_password_candidate` | `author_hash` |
| `review_list`, `user_storage` | `user_hash` (default) |

Not wrapped (ungated in every mode):

- `user_card`, `vouch_token` — intentionally, so the server receives every card and token it is offered and can resolve chains (see the note under [Access Modes](#access-modes)).
- `review_post_right(_candidate)`, `review_revoke_right(_candidate)`.

**Differences from the target design above:**

- `max_depth` is not enforced. Any reachable path passes, and the error body carries no `max_depth`.
- `guarded` and `trust` behave the same: only writes are gated. Shape reads / sync are not gated in any mode until [Read Gating](#read-gating-read-sessions) lands.
- A rejection surfaces as a writer check error, not as a plug-level `403` before the controller.

---

## Read Gating (Read Sessions)

Reads are gated in **`trust` mode only**. In `open` and `guarded` modes the read gate passes every request through, with or without a token.

A read session is **per shape**. Opening one proves possession (PoP) **and** checks the vouch chain for `device.<sn>.storage.read.<shape>`. Each read then only checks that the token is valid for the shape of the requested table.

### Why sessions instead of per-request checks

Shape reads are Electric long-polls. A live collection re-requests about every 20s, and a client holds many collections (7+ per open dialog). Challenges are single-use and cost a round trip, and an ML-DSA-87 signature is ~4.6 KB. The chain check is a recursive CTE. Doing both on each poll would double the request count and put a signature and a CTE on every request. So the client proves possession and passes the chain check **once per shape per session**.

### Opening a session

```
GET  /electric/v1/challenge        → {challenge_id, challenge, expires_in}
POST /electric/v1/read_session     {user_hash, shape, challenge_id, signature}
                                   ← 200 {token, shape, expires_in: 300}
                                   ← 400 {"error": "unknown_shape"}
                                   ← 401 {"error": "Invalid or expired challenge"}
                                   ← 401 {"error": "unknown_user"}      (no user_card for user_hash)
                                   ← 401 {"error": "invalid_signature"}
                                   ← 403 {"error": "not_in_trust_chain", "max_depth": <max_depth>}
```

1. Resolve `shape` with `Chat.Data.Shapes.by_name/1` (shape name, e.g. `dialog_messages`, `file`). Unknown → `400`.
2. Consume the challenge (`Chat.Challenge.get/1`, single use).
3. Look up `sign_pkey` from `user_cards` for `user_hash`. The caller must have ingested its `user_card` first. `user_card` ingest is never chain-gated, so this works in every mode.
4. Verify `ML-DSA-87.verify(challenge, signature, sign_pkey)`. The signature format is the same as ingest PoP, so the client reuses its existing signer.
5. Check the chain:
   - no owner registered → pass;
   - `user_hash` is the owner → pass;
   - `VouchToken.chain_distance(owner_hash, user_hash, "device.<sn>.storage.read.<shape>")` returns `{:ok, distance}` with `distance ≤ max_depth` → pass;
   - otherwise → `403 not_in_trust_chain`.
6. Issue `token` = 32 random bytes, base64url. Store `{token, user_hash, shape, expires_at}` in ETS.

The endpoint runs the same checks in every mode. Clients open sessions **lazily**: only after a read returns `401 read_session_required`, which happens only in `trust` mode. When the owner switches to `trust`, live streams get `401`, open sessions, and resume.

### Scope: `storage.read.<shape>`

The scope suffix is the **shape name** (`shape_name/0` of the shape module), the same names write scopes use (`storage.write.<shape>`). A request's `?table=` maps to its shape through the `Chat.Data.Shapes` registry: the main table (`schema_module`) and the versions table (`versions_schema`) both map to the owning shape. For example, `dialog_messages` and `dialog_messages_versions` both need a `dialog_messages` session, and `files` needs a `file` session. A vouch at `device.<sn>.storage.read` covers every shape through prefix matching.

This differs from write scopes, which use shape names (`storage.write.dialog_messages`, `storage.write.file`).

### Session store: `Chat.Pq.ReadSession`

- ETS table owned by a GenServer, with periodic cleanup of expired entries (same pattern as `Chat.Challenge`).
- **TTL: 5 minutes**, fixed from issue time. No sliding refresh.
- **No invalidation.** No logout, no revoke, no vouch-driven eviction. A session ends only when its TTL expires. Revoking a vouch therefore takes effect within 5 minutes, when the caller's sessions expire and the next open fails the chain check.
- Not persisted. A restart drops all sessions, and clients get `401` and open new ones.
- A session is bound to the device that issued it (ETS is local).

### Presenting the token

Every read carries `Authorization: Bearer <token>` for the session of that table's shape:

- Electric's TS client sets it via `shapeOptions.headers`, and one-shot reads (`readShapeOnce`) add it to `fetch`.
- A header, not a query param, keeps the token out of URLs, logs, and the shape cache key.
- CORS: the `:electric` pipeline uses `CORSPlug` default request headers, which already include `Authorization`.

The client keeps one session per shape. All collections of the same shape (e.g. `dialog_messages` and `dialog_messages_versions` across several dialogs) share it. The client opens a new session before the TTL expires (e.g. at 4 min) or on any `401 read_session_required`.

### What the gate checks

`ChatWeb.Plugs.ElectricReadGate` runs after `ElectricTableGuard`, so the table is already known. It maps the table to its shape:

1. **Mode is not `trust`** → pass.
2. **No owner registered** → pass.
3. **Valid session** — the `Authorization: Bearer` token exists in ETS, is not expired, and its `shape` equals the requested table's shape → pass.
4. **Otherwise** (no header, unknown or expired token, or token for another shape) → `401 {"error": "read_session_required", "shape": "<shape>"}`.

The gate does no signature check and no chain lookup. Both happened when the session was opened.

### Nothing is exempt

Unlike writes, **no shape is exempt** from read gating in `trust` mode, including `user_card` and `vouch_token`. The write-side exemption exists because the server needs cards and tokens to resolve chains, and the server reads its own database directly. Leaving `vouch_tokens` readable would expose the trust topology (see [Open Questions §4](#open-questions)).

An unvouched client can still ingest its `user_card`, but opening a read session for any shape fails with `403 not_in_trust_chain`. The frontend shows a "waiting for approval" state.

### Gated surfaces

Every route that serves synced data gets the read gate. Otherwise gating `/shapes` alone is bypassable:

| Route | Notes |
|-------|-------|
| `GET /electric/v1/shapes` | Client-controlled shapes |
| legacy `sync(...)` routes (`/electric/v1/dialog_message`, …) | Session for the schema's shape. Still used by chat-frontend `main`. Gate or remove |
| `GET /electric/v1/file_chunk/:file_id/:chunk_index` | Session for shape `file_chunk` |
| `GET /electric/v1/file_chunk_status` | Session for shape `file_chunk` |

Not gated: `/status`, `/challenge`, `/read_session`, `/system_identifier` (needed before authenticating).

### HTTP caching

Electric sends `cache-control: public` on shape responses. In `trust` mode the read gate rewrites it to `private` and adds `Vary: Authorization`. Otherwise a shared cache or the frontend service worker (`sw.js` intercepts `/shapes`) could serve gated data to an unauthorized client.

### Peer servers

A peer server reads the same way: it opens a read session per shape, signed with its server identity key, and sends the Bearer token from its Electric client. This requires the peer's server identity to have a `user_card` on the target device. How that card gets there is not yet specified.

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
  |  --- open read session (per shape, trust mode) ---
  |                                |
  |-- GET /challenge ------------->|
  |<-- {challenge_id, challenge} --|
  |-- POST /read_session --------->|
  |   {user_hash, shape,           |  sign_pkey from user_cards, ML-DSA verify,
  |    challenge_id, signature}    |  chain check storage.read.<shape>,
  |                                |  store {token, user_hash, shape} in ETS
  |<-- {token, shape, 300} or 403 -|
  |                                |
  |  --- shape read (sync) --------
  |                                |
  |-- GET /shapes?table=… -------->|
  |   Authorization: Bearer <tok>  |
  |                                |
  |   [ElectricReadiness]          |  DB + Electric up?
  |   [ElectricTableGuard]         |  table allowed?
  |   [ElectricReadGate]           |
  |     - not trust? pass          |
  |     - no owner? pass           |
  |     - token valid for shape?   |  ETS lookup only, no sig / chain
  |         pass                   |
  |     - else? 401                |  read_session_required
  |   [HexToBase64Electric]        |  long-poll
  |                                |
  |<-- shape log ------------------|
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

In Progress. Server identity (`Chat.Pq.ServerIdentity`), device identity (`Chat.DeviceId`), owner bootstrap (`Chat.Pq.OwnerBootstrap`), gate mode storage in AdminDB, and admin sandbox UI with gate mode switching are implemented. Write-side vouch chain enforcement is implemented per shape via `Chat.Pq.WriteGate` (see [Current implementation](#current-implementation-chatpqwritegate)).

Pending:

- The `ElectricAccessGate` plug (PoP + vouch chain enforcement in the router pipeline).
- `max_depth` setting and enforcement.
- Read gating in `trust` mode (see [Read Gating](#read-gating-read-sessions)):
  - `Chat.Pq.ReadSession` ETS store (per shape, 5 min TTL) and `POST /electric/v1/read_session` (PoP + `storage.read.<shape>` chain check).
  - `ChatWeb.Plugs.ElectricReadGate` on `/shapes`, legacy `sync` routes, and file_chunk reads.
  - `cache-control: private` + `Vary: Authorization` in `trust` mode.
  - chat-frontend: open sessions lazily per shape on `401`, send `Authorization: Bearer` on shape reads and `readShapeOnce`, show "waiting for approval" on `403`.

## Open Questions

1. **Should the owner be able to delegate vouching rights?** An approved user with `device.<sn>.storage.write` can already vouch for others (that's the transitive chain). The question is whether there should be a narrower scope that grants ingest but not the ability to vouch further.
2. ~~Should there be a "pending" state where unapproved users' requests are queued rather than rejected?~~ **Out of scope** — deferred to a separate feature.
3. **Where to store owner identity and mode setting?**

   Resolved. Owner identity is stored under `:pq_admin` (`%{user_hash, sign_pkey}`) in AdminDB (CubDB). Access mode is stored under `:pq_gate_mode` (`:open` / `:guarded` / `:trust`). Server identity keypair is stored under `:pq_server_identity`. On first boot `ServerIdentity` seeds `:pq_gate_mode` to `:open` via `AdminDb.put_new/2`. Owner registration happens via `OwnerBootstrap.maybe_register_owner/2` on first `user_card` ingest.

   Sub-question: should AdminDB settings be **replicated to the backup drive**? On the platform, each USB drive gets its own PG instance with logical replication between main and internal. AdminDB is currently single-drive — backup requires explicit copy logic.

4. **Should chain distance be visible to users?** Transparency aids debugging ("why was I rejected?") but also reveals the trust topology. Options: visible to owner only, visible to each user for their own distance, or fully opaque.

5. **Offline chain evaluation.** ~~Should vouch attestations be structured as self-contained signed tokens?~~ **Yes** — vouch tokens must be self-contained signed attestations so the gate can evaluate trust without live lookups. Chain-distance computation works from the token chain alone, enabling offline evaluation. See [Vouch Tokens](pq_vouch_tokens.in_progress.md) for the self-contained token structure.

6. **Should a future version add composite scoring?** Chain distance is sufficient as a starting point, but richer signals (vouch quality, behavioral patterns, tenure) could be layered in later if the simple model proves too coarse. Keeping this as a known extension point.

7. **Mutual authentication (future).** Currently the client authenticates to the server (PoP + sync key). A future extension could have the server prove its identity to the client — the client verifies it is syncing with the real `device.<sn>`, not a rogue server. This matters on LANs where DNS/mDNS spoofing is trivial. Possible approaches: server presents a signed challenge using a device identity key, or the sync key exchange during discovery is upgraded to a mutual key-agreement protocol.

---

## References

- [Vouch Tokens](pq_vouch_tokens.in_progress.md) — schema, graph traversal CTE, scope attenuation, cache
- [Optical Handshake Flow](../flows/pq_optical-handshake.livemd) — contact establishment via physical proximity

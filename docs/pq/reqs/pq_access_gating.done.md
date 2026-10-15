# PQ API Access Gating

## Purpose

Control who can read and write data through the Electric API. Three distinct surfaces are gated:

- **Write (ingest)** — vouch-chain + PoP, controlled by access mode (`open` / `guarded` / `trust`).
- **Read / sync (shape subscriptions)** — gated in `trust` mode only: a per-shape [read session](#read-gating-read-sessions) (PoP + chain check on open), then a Bearer token on every read.
- **Network discovery** — captures the peer's sync key so clients can establish sync relationships.

The system starts in `open` mode. The first user to ingest a `user_card` registers unconditionally and becomes the **owner** (persisted in AdminDB). While in `open` mode, anyone with valid PoP can read and write. The owner can escalate to `guarded` (writes chain-gated, reads open) or `trust` (all access chain-gated). The server provides nothing to clients unless they ask — a client must know the device serial number to request access.

---

## Access Modes
| Mode | `user_card` / `vouch_token` ingest | Other ingest | `user_card` / `vouch_token` reads | Other shape reads / sync |
|------|------------------------------------|--------------|------------------------------------|--------------------------|
| `open` | Anyone with valid PoP | Anyone with valid PoP | Anyone (not gated) | Anyone (not gated) |
| `guarded` | Anyone with valid PoP (never chain-gated) | Chain-gated (see [Trust Gate](#trust-gate)) | Anyone (not gated) | Anyone (not gated) |
| `trust` | Anyone with valid PoP (never chain-gated) | Chain-gated (see [Trust Gate](#trust-gate)) | Anyone (never gated) | Read session + chain-gated (see [Read Gating](#read-gating-read-sessions)) |

Default mode: `open` (preserves current behavior). `guarded` mode gates writes via vouch chain and leaves reads open. `trust` mode gates **all** access — reads, writes, and peer sync — via PoP + vouch chain. The same mechanism applies to users and peer servers alike.

> **`user_card` and `vouch_token` are never chain-gated — neither writes nor reads.** They are the inputs to chain resolution: `user_cards` supply `sign_pkey` for each `user_hash`, and vouch tokens are the graph edges. The server must accept every one it is offered, in any mode, so it can resolve chains, and every client and peer must be able to read them so it can learn the trust topology it needs to authenticate. Gating them would be circular — a user couldn't become reachable without first being reachable, and a missing intermediate card or token would break chains for everyone downstream of it. Both still go through their shape's own PoP / signature checks on writes. Accepting a card or token grants nothing by itself: the chain check on other shapes decides what the user can access.

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
4. **Keys**: sign (ML-DSA-87), crypt (ML-KEM-1024) and contact (secp256k1) keypairs, same set as a user identity. Identities created before contact keys existed get them added on the next boot.
5. **User card**: The server has a `user_card` named `SyncBot_<device_id>` (see [Server User Card](#server-user-card)).

### Server User Card

The server identity is a user like any other on the wire, so it needs a `user_card`. The `SyncBot_` prefix tells people it is an auxiliary identity that syncs data between devices, not a person.

- **Name**: `SyncBot_<device_id>` (device id from `Chat.DeviceId`).
- **Own card**: the device's own SyncBot card is stored into PostgreSQL after migrations on every repo start. The upsert keeps the newer `owner_timestamp`, so repeating it is a no-op. Written directly (not through `ShapeWriter`), so it never triggers `OwnerBootstrap` and cannot claim device ownership.
- **Discovery**: `GET /electric/v1/device_identity` exposes the SyncBot's `user_hash` and `sign_pkey` (see [Device Identity Endpoint](#device-identity-endpoint)). Peer devices use this to know which identity to vouch for.
- **Peer cards**: arrive through normal `user_card` sync — `user_card` reads are exempt from gating (see [Read-exempt shapes](#read-exempt-shapes)), so peers always receive each other's SyncBot cards.

### Device Identity Endpoint

`GET /electric/v1/device_identity` — always accessible (no Electric readiness, no auth). Returns the three things a peer needs to know about this device:

```json
{
  "device_id": "<serial number>",
  "sync_bot": { "user_hash": "u_…", "sign_pkey": "<base64>" },
  "admin":    { "user_hash": "u_…", "sign_pkey": "<base64>" }
}
```

| Field | Meaning | null when |
|-------|---------|-----------|
| `device_id` | Device serial number. Scopes are `device.<device_id>.storage.*` | never |
| `sync_bot` | This device's SyncBot identity — the `user_hash` that will request read sessions on the peer | `ServerIdentity` not started (shouldn't happen) |
| `admin` | The owner / vouch-chain root of this device | no owner registered yet |

A peer uses this to know **which `user_hash` to vouch for** — the `sync_bot.user_hash` is who will be authenticating when reading shapes from the peer.

### Network Discovery

The server provides nothing unless the client asks — a client must know the device serial number. **Network discovery** captures the peer's identity so that:

- A peer server can authenticate against the target device's gate (`sync_bot.user_hash`).
- The owner knows which identity to approve (`sync_bot.user_hash` from the peer's `device_identity`).

The exact discovery protocol (mDNS, optical handshake extension, manual entry) is defined by the discovery flow, not this requirement. `device_identity` is the identity exchange endpoint all discovery methods use.

### SyncBot Card Push

When device A discovers device B (via LAN detection or manual entry in the admin panel), A **pushes its SyncBot `user_card` to B** via B's `/ingest` endpoint. This is necessary so B knows A's identity and B's admin can approve A for read/write access.

The push happens early in the `PeerConnector` flow — after the system identifier is resolved but before `PeerSync` starts shape consumers. The mechanism:

1. Fetch a one-time challenge from B (`GET /electric/v1/challenge`).
2. Build the SyncBot's `user_card` insert mutation (from `ServerIdentity` + `ServerCard`).
3. Sign the challenge with the server identity key.
4. `POST /ingest` to B with `auth` (challenge + signature) and the `user_card` mutation.

This always succeeds regardless of B's access mode — `user_card` ingest is never chain-gated (see the note under [Access Modes](#access-modes)). The push is **idempotent**: if the card already exists on B with the same or newer `owner_timestamp`, the upsert is a no-op. A network failure during the push retries with the same backoff as the rest of `PeerConnector`, since the card must land before shape sync can work in `trust` mode.

After the card lands on B, B's admin sees `SyncBot_<A's device_id>` in the user list and can approve it (issue a vouch token). Until approved, A's shape consumers enter [Awaiting approval](#awaiting-approval) with backoff.

### Peer-to-Peer Sync

When device A syncs from device B, device A acts as a client — it opens a [read session](#read-gating-read-sessions) on B with its own server key via PoP, and B checks A against the vouch chain (in `trust` mode). The mechanism is identical to a user reading shapes: same read gate, same check, same vouch token scopes.

For this to work, B must know A's SyncBot identity (a `user_card` for A's `sync_bot.user_hash` must exist on B). The card is pushed to B during peer connection setup (see [SyncBot Card Push](#syncbot-card-push)).

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

Writes and reads are gated at two levels:

- **Writes** — `Chat.Pq.WriteGate`, per shape inside the ingest writer. The caller proves possession with a one-time signed challenge in the request body. See [Write Gate](#write-gate-chatpqwritegate).
- **Reads** — `ChatWeb.Plugs.ElectricReadGate`, a plug in the router pipeline. The caller presents a Bearer token from a read session. See [Read Gating](#read-gating-read-sessions).

```
scope "/" do
  pipe_through ChatWeb.Plugs.ElectricReadiness

  scope "/" do
    pipe_through ChatWeb.Plugs.ElectricChallengeInjector
    post "/ingest", ElectricController, :ingest       # write gate runs per shape inside the writer
    post "/ingest_each", ElectricController, :ingest_each
  end
end

scope "/electric/v1/shapes" do
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricTableGuard
  pipe_through ChatWeb.Plugs.ElectricReadGate         # Bearer read session + vouch chain
  forward "/", ChatWeb.Plugs.HexToBase64Electric
end
```

Reads follow [Read Gating § What the gate checks](#what-the-gate-checks).

### Write Gate (`Chat.Pq.WriteGate`)

Write gating is enforced per shape, inside the ingest writer, not in a router plug. `Chat.Pq.WriteGate.and_gate/3` wraps a shape's `check` callback. The chain check runs only after the shape's own PoP/ownership check returns `:ok`:

> **Why per-shape, not a router plug?** A router-level plug would need to parse mutations to identify the caller (each shape uses a different owner field — `sender_hash`, `reactor_hash`, `uploader_hash`, etc.) and to distinguish gated from ungated shapes in mixed `/ingest_each` batches. It would duplicate logic that already runs per mutation inside the writer, with no behavioral gain — the client sees the same `403` body either way. Per-shape enforcement also lets each shape's PoP check run first, so the chain check only fires for callers who already proved key ownership.

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
5. Otherwise, `VouchToken.chain_distance(owner_hash, user_hash, "device.<id>.storage.write.<shape>", WriteGate.max_depth())` must return `{:ok, _}`. If it doesn't, the mutation is rejected with `{:error, "not_in_trust_chain"}`.

`ElectricController` turns that check error into the response:

- `/ingest` → `403 {"error": "not_in_trust_chain", "max_depth": <max_depth>}`.
- `/ingest_each` → the row result is `{"index": i, "status": "error", "error": "not_in_trust_chain", "max_depth": <max_depth>}`. The response is `403` when every failed row is `not_in_trust_chain`, and `422` when any row failed for another reason.

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

**Known limitations:**

- `max_depth` is fixed at `VouchToken.default_max_depth/0` (7). There is no owner setting yet.
- `guarded` and `trust` gate writes the same way. `trust` additionally gates reads (see [Read Gating](#read-gating-read-sessions)).

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

Client rules (lazy opening, sharing, renewal, stream wiring) are in [Client Behaviour § Reads](#reads).

### What the gate checks

`ChatWeb.Plugs.ElectricReadGate` runs after `ElectricTableGuard`, so the table is already known. It maps the table to its shape:

1. **Mode is not `trust`** → pass.
2. **No owner registered** → pass.
3. **Exempt shape** (`user_card`, `vouch_token`) → pass. See [Read-exempt shapes](#read-exempt-shapes).
4. **Valid session** — the `Authorization: Bearer` token exists in ETS, is not expired, and its `shape` equals the requested table's shape → pass.
5. **Otherwise** (no header, unknown or expired token, or token for another shape) → `401 {"error": "read_session_required", "shape": "<shape>"}`.

The gate does no signature check and no chain lookup. Both happened when the session was opened.

### Read-exempt shapes

**`user_card` and `vouch_token` reads are exempt** from read gating in `trust` mode, same as their writes. The reasoning is the same: they are the inputs to chain resolution, and gating them would be circular.

This also solves peer sync bootstrap: when device A syncs from device B, A reads B's `user_cards` (including `SyncBot_B`) and `vouch_tokens` without a session. A then has the trust data it needs to open read sessions for everything else.

An unvouched client can still ingest its `user_card` and read `user_cards` / `vouch_tokens`, but opening a read session for any other shape fails with `403 not_in_trust_chain`. The client enters [Awaiting approval](#awaiting-approval).

### Gated surfaces

Every route that serves synced data gets the read gate. Otherwise gating `/shapes` alone is bypassable:

| Route | Notes |
|-------|-------|
| `GET /electric/v1/shapes` | Client-controlled shapes |
| `GET /electric/v1/file_chunk/:file_id/:chunk_index` | Session for shape `file_chunk` |
| `GET /electric/v1/file_chunk_status` | Session for shape `file_chunk` |

Not gated: `/status`, `/challenge`, `/read_session`, `/system_identifier`, `/device_identity` (needed before authenticating).

### HTTP caching

Electric sends `cache-control: public` on shape responses. In `trust` mode the read gate rewrites it to `private` and adds `Vary: Authorization`. Otherwise a shared HTTP cache could serve gated data to an unauthorized client. The frontend service worker does not cache `/api` (Electric long-polls and ingest pass through untouched) and must keep it that way.

### Peer servers

A peer server reads the same way: it opens a read session per shape, signed with its server identity key, and sends the Bearer token from its Electric client. This requires the peer's server identity to have a `user_card` on the target device.

The peer's SyncBot card arrives on the target device through an active push: when A connects to B, A pushes its own SyncBot card via `/ingest` (see [SyncBot Card Push](#syncbot-card-push)). Additionally, since `user_card` and `vouch_token` reads are exempt (see [Read-exempt shapes](#read-exempt-shapes)), cards also propagate through normal Electric sync once shape consumers are running.

- Having a card only makes the peer a known user, so it gets past `401 unknown_user`. Gated reads still need the vouch chain: in `trust` mode someone has to vouch for `SyncBot_<peer_device_id>`.
- `GET /electric/v1/device_identity` tells the peer the `sync_bot.user_hash` it will need to vouch for, and the `admin` identity (the vouch-chain root) — useful for the Owner UI to show which device's SyncBot needs approval.

---

## Client Behaviour

Rules for chat-frontend and any other client. Bots and peer servers follow the [Reads](#reads) part.

The client never needs to know the access mode. It reacts to responses. In `open` mode none of the gate responses below occur, so the same code runs in every mode.

### Identity first

1. **Ingest the `user_card` alone** before any other write: one mutation in its own request. `/ingest` is one transaction, so a card batched with a gated mutation rolls back with it. The card is the one write that must always land.
2. **`401 unknown_user`** from `/read_session` means this device has no card for the caller (new device, wiped database). Ingest the card (rule 1), then open the session again, once.

### Writes

How a blocked write looks today:

| Endpoint | Blocked write |
|----------|---------------|
| `POST /ingest` | `403 {"error": "not_in_trust_chain", "max_depth": N}` |
| `POST /ingest_each` | row result `{"status": "error", "error": "not_in_trust_chain", "max_depth": N}`. The response is `403` if every failed row is blocked, `422` if any row failed for another reason |

**Decide per row, by the `error` string.** A `422` batch can mix blocked rows with real validation failures, so the status code alone does not tell them apart.

1. **Not permanent.** A blocked write is not a validation failure. Do not quarantine or drop it, and do not roll back the user's optimistic state. Keep it pending in the outbox. (`ingest.ts` currently treats any `422` as permanent and anything else, `403` included, as transient. Blocked rows must be neither.)
2. **Not transient either.** Do not put it on the backoff retry schedule. Pause outbox draining for this identity and enter [Awaiting approval](#awaiting-approval). Resume draining when approval is detected.
3. **Partial batches.** In an `/ingest_each` batch, rows that succeeded stay committed. Only the blocked rows stay pending.
4. **Never blocked:** `user_card` and `vouch_token` writes, `review_post_right(_candidate)` and `review_revoke_right(_candidate)`, and any write by the owner.
5. **File uploads.** `PUT /file_chunk/...` has no chain check of its own; the `file` row carries it. Upload chunks only after the `file` row is accepted. If the `file` row is blocked, hold the chunks with it. The server accepts chunks for a file that has no row, so uploading first would leave orphan chunks on the device.

### Reads

The session endpoint is described in [Opening a session](#opening-a-session).

1. **Lazy.** Send no session until a read returns `401 {"error": "read_session_required", "shape": S}`. Then open a session for `S`. The body names the shape, so the client needs no table-to-shape map.
2. **One session per shape, shared.** Keep a per-identity map `shape → {token, expires_at}` and at most one open in flight per shape. Concurrent `401`s for the same shape await the same promise. One open dialog has 5 collections over 4 shapes, and they all get `401` at once when the mode switches.
3. **Renew** when less than 60 s remain (`expires_in` is 300), and on any `401 read_session_required` even if the local token looks valid. A server restart drops every session.
4. **Electric streams** (`@electric-sql/client`, used by the TanStack Electric collections through `shapeOptions`):
   - `headers: { Authorization: () => bearerFor(shape) }`. Use a function, not a string, so every long-poll picks up a renewed token. `bearerFor` returns `"Bearer <token>"`, or `""` before a session exists.
   - `onError`: for a `FetchError` with status `401` and `json.error === "read_session_required"`, open or renew the session for `json.shape` and return `{}`. The retry re-reads the header function.
   - If opening the session returns `403`, enter [Awaiting approval](#awaiting-approval) and return `undefined` to stop the stream. Do not keep it retrying through `onError`: the client's consecutive-retry guard would end it anyway. The approval probe restarts stopped streams.
   - Leave all other errors to the existing handling.
5. **One-shot reads** (`readShapeOnce`, `GET /file_chunk/:file_id/:chunk_index`, `GET /file_chunk_status`): send the same header. On `401 read_session_required`, open the session and retry once. A second `401` is an error.
6. **Service worker video streamer.** `sw.js` fetches `/file_chunk/...` itself and holds no identity key, so it never opens sessions:
   - The page includes the current `file_chunk` token in the video session it posts to the worker.
   - The worker sends `Authorization: Bearer <token>` on chunk fetches.
   - On `401` the worker asks the page for a fresh token (a `need-token` message, like the existing `need-session`), retries once, then fails the range.
7. **Tokens are secrets.** Keep them in memory only: not in URLs, logs, IndexedDB, or the outbox. After a reload, sessions are opened lazily again.
8. **Shape barriers.** A write that waits for its txid in a collection (`awaitTxId`) must not wait on a stream that is stopped for approval. It would only time out. While the stream's shape is blocked, treat the ingest `200` as the commit and resolve the barrier.

### Awaiting approval

Entered on `403 not_in_trust_chain` from `/read_session` (only in `trust` mode) or on a `not_in_trust_chain` write (`guarded` or `trust`).

- **UI.** Show "Waiting for approval by the device owner" together with the user's own `user_hash`, so the owner can find and approve them. `max_depth` is not user-facing.
- **Guarded mode:** reads still work. The app stays usable read-only, and sends queue as pending.
- **Trust mode:** blocked shapes show no data. Locally persisted data stays visible.
- **Per shape.** A vouch can cover a single shape (`storage.read.file`). Track blocked shapes individually. Show the banner when any shape the current screen needs is blocked.
- **Probing.** Nothing pushes an approval, so the client polls:
  - Probe 15 s after entering the state, then double the interval up to a 5 min cap.
  - Also probe immediately on a "Check again" button, when the app becomes visible, and on network reconnect.
  - Blocked read: the probe opens a session for a blocked shape. On success, restart that shape's streams.
  - Blocked write: the probe sends the first blocked outbox entry. On success, resume draining.
  - Each probe costs one challenge and one ML-DSA signature.
- **Leaving.** Any successful session open or write for a shape clears that shape's blocked state.
- **Revocation.** An approved client whose vouch is revoked gets `401` on its next read within 5 min. Renewing then returns `403`, which puts it into this state. Local data and pending writes are kept.

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
  |   [ChallengeInjector]          |
  |   [ElectricController.ingest]  |  writer
  |     per shape: WriteGate       |  PoP verify + mode check:
  |     - no owner? pass + claim   |    - no owner → pass, register as owner in AdminDB
  |     - open? PoP ok → pass      |    - open → PoP valid → pass
  |     - owner? pass              |    - owner → always pass
  |     - guarded? chain check     |    - guarded → chain_distance ≤ max_depth → pass (writes)
  |     - trust? chain check       |    - trust → chain_distance ≤ max_depth → pass (all)
  |     - else? 403                |    - else → 403
  |                                |
  |<-- {txid} or error ------------|
```

---

## Status

Done. Server identity (`Chat.Pq.ServerIdentity`), device identity (`Chat.DeviceId`), owner bootstrap (`Chat.Pq.OwnerBootstrap`), gate mode storage in AdminDB, and admin sandbox UI with gate mode switching are implemented. Write-side vouch chain enforcement is implemented per shape via `Chat.Pq.WriteGate` (see [Write Gate](#write-gate-chatpqwritegate)).

Read gating (server side) is implemented:

- `Chat.Pq.ReadSession` — ETS store, per shape, 5 min fixed TTL, periodic sweep.
- `Chat.Pq.ReadGate` — PoP + `storage.read.<shape>` chain check; `POST /electric/v1/read_session` (`ChatWeb.ReadSessionController`).
- `ChatWeb.Plugs.ElectricReadGate` on `/shapes` (shape from `?table=`, versions tables map to the owning shape) and on `file_chunk/:file_id/:chunk_index` + `file_chunk_status` (shape `file_chunk`). Passing responses get `cache-control: private` + `vary: authorization`. Read gate exempts `user_card` and `vouch_token` shapes (`@exempt_shapes`).
- `max_depth` in the `403` body and in the read chain check is `VouchToken.default_max_depth/0` (7) until the setting exists.

Read gating (network sync client — this device reading from a peer) is implemented:

- `Chat.NetworkSynchronization.Electric.ReadSessionClient` — `GET /challenge`, signs with the server identity key, `POST /read_session`.
- `Chat.NetworkSynchronization.Electric.ReadSessions` — per `{peer_url, shape}` tokens in ETS (memory only), lazy open on `401 read_session_required`, one in-flight open per key, renewal when < 60 s remain. `request/4` wraps any HTTP call: Bearer header, open on `401`, retry once.
- `Chat.NetworkSynchronization.Electric.GatedFetch` — `Electric.Client.Fetch` wrapper used by `ShapeConsumer` and `DeferredStore` refetch. The `401` → open → retry happens inside the fetch, so the live stream keeps its offset.
- A failed open (`not_in_trust_chain`, `unknown_user`) stops the shape stream; `ShapeConsumer` reports `awaiting approval: <reason>` and retries with backoff starting at 15 s, doubling to 5 min.
- `SyncSource` chunk fetches (`file_chunk`) go through `ReadSessions.request/4`.
- LAN detection treats a `401 read_session_required` probe response as a (gated) Electric peer.

Device identity endpoint is implemented (see [Device Identity Endpoint](#device-identity-endpoint)):

- `ChatWeb.DeviceIdentityController` — `GET /electric/v1/device_identity` returns `device_id`, `sync_bot` and `admin` identities.

SyncBot card (`Chat.NetworkSynchronization.Electric.SyncBotCardPusher`) is implemented:

- The server's SyncBot identity (`SyncBot_<device_id>`) is a user like any other, with keypairs generated by `ServerIdentity` and stored in AdminDB.
- `SyncBotCardPusher.push/1` builds the SyncBot `user_card` from `ServerIdentity`, fetches a challenge from the peer, signs it, and POSTs `/ingest`.
- Called by `PeerConnector` after system identifier resolution, before starting `PeerSync`.
- Idempotent: existing card with same-or-newer timestamp is a no-op. Network failures retry with PeerConnector backoff.

`max_depth` setting is implemented:

- Stored in AdminDB under `:pq_max_depth`. Both `WriteGate.max_depth/0` and `ReadGate.max_depth/0` read from `AdminDb.get(:pq_max_depth)` with fallback to `VouchToken.default_max_depth/0` (7).
- Admin sandbox UI exposes the setting (`set_max_depth` event in `AdminSandboxLive.Index`).

chat-frontend [Client Behaviour](#client-behaviour) is implemented:

- `readSession.ts` — lazy session open on `401 read_session_required`, per-shape token map, Bearer header via function reference, renewal.
- `ingest.ts` — `NOT_IN_TRUST_CHAIN` detection, separate from validation errors.
- `outbox.ts` — `awaiting_approval` hold reason, pauses draining for blocked identity, partial batch handling.
- `shapeRead.ts` — `onError` 401 handling, session open + retry.
- UI indicators in `ChatWindow.vue` (`⏳` for awaiting approval on messages and edits).

No pending items — all features described in this requirement are implemented.

## Open Questions

1. **Should the owner be able to delegate vouching rights?** An approved user with `device.<sn>.storage.write` can already vouch for others (that's the transitive chain). The question is whether there should be a narrower scope that grants ingest but not the ability to vouch further.
2. ~~Should there be a "pending" state where unapproved users' requests are queued rather than rejected?~~ **Out of scope** — deferred to a separate feature.
3. **Where to store owner identity and mode setting?**

   Resolved. Owner identity is stored under `:pq_admin` (`%{user_hash, sign_pkey}`) in AdminDB (CubDB). Access mode is stored under `:pq_gate_mode` (`:open` / `:guarded` / `:trust`). Server identity keypair is stored under `:pq_server_identity`, its signed `user_card` under `:pq_server_card`. On first boot `ServerIdentity` seeds `:pq_gate_mode` to `:open` via `AdminDb.put_new/2`. Owner registration happens via `OwnerBootstrap.maybe_register_owner/2` on first `user_card` ingest.

   Sub-question: should AdminDB settings be **replicated to the backup drive**? On the platform, each USB drive gets its own PG instance with logical replication between main and internal. AdminDB is currently single-drive — backup requires explicit copy logic.

4. **Should chain distance be visible to users?** Transparency aids debugging ("why was I rejected?") but also reveals the trust topology. Note: vouch token reads are now exempt from gating (see [Read-exempt shapes](#read-exempt-shapes)), so the token graph is already visible to anyone who syncs. The remaining question is whether *computed* chain distance should be surfaced in the UI. Options: visible to owner only, visible to each user for their own distance, or fully opaque.

5. **Offline chain evaluation.** ~~Should vouch attestations be structured as self-contained signed tokens?~~ **Yes** — vouch tokens must be self-contained signed attestations so the gate can evaluate trust without live lookups. Chain-distance computation works from the token chain alone, enabling offline evaluation. See [Vouch Tokens](pq_vouch_tokens.in_progress.md) for the self-contained token structure.

6. **Should a future version add composite scoring?** Chain distance is sufficient as a starting point, but richer signals (vouch quality, behavioral patterns, tenure) could be layered in later if the simple model proves too coarse. Keeping this as a known extension point.

7. **Mutual authentication (future).** Currently the client authenticates to the server (PoP + sync key). A future extension could have the server prove its identity to the client — the client verifies it is syncing with the real `device.<sn>`, not a rogue server. This matters on LANs where DNS/mDNS spoofing is trivial. Possible approaches: server presents a signed challenge using a device identity key, or the sync key exchange during discovery is upgraded to a mutual key-agreement protocol.

---

## References

- [Vouch Tokens](pq_vouch_tokens.in_progress.md) — schema, graph traversal CTE, scope attenuation, cache
- [Optical Handshake Flow](../flows/pq_optical-handshake.livemd) — contact establishment via physical proximity

# Electric Network Sync

## Purpose

Synchronize PostgreSQL-backed data (`user_cards`, `user_storage`) between BuckitUp LAN peers using Electric shape streaming. Complements the existing GraphQL/CubDB sync which handles chat messages, dialogs, and rooms.

## Architecture

### Sync Model

Each device runs an Electric-capable HTTP server. When a peer is discovered on the LAN, the local device opens long-polling Electric shape streams against the peer's `/electric/v1/shape` endpoint. Incoming rows are upserted into the local PostgreSQL database.

```
Device A                                   Device B
┌────────────────┐                         ┌────────────────┐
│  PostgreSQL    │  Electric Shape HTTP    │  PostgreSQL    │
│  user_cards    │◄─────────────────────── │  user_cards    │
│  user_storage  │  GET /electric/v1/...   │  user_storage  │
│                │  (long-poll, offset)    │                │
└────────────────┘                         └────────────────┘
```

- Transport: `Electric.Client` (Elixir HTTP long-poll)
- Real-time: yes (live shape streaming with offset tracking)
- Resume: built-in via `ResumeMessage` persisted to CubDB

### Peer Identification

Peers are identified by their PostgreSQL `system_identifier` — a unique 64-bit value generated at cluster init. This is more reliable than IP addresses in DHCP environments.

Each device exposes `GET /electric/v1/system_identifier` which returns `{"system_identifier": "<value>"}`. The identifier is fetched once when a peer connection is established and used as the key for offset storage.

### Supervision Tree

```
NetworkSynchronization.Supervisor
├── DynamicSupervisor           (existing GraphQL workers)
├── Registry                    (existing)
├── LanDetector                 (existing)
├── DynamicSupervisor           (ElectricDynamic — manages PeerSync instances)
└── Registry                    (ElectricRegistry — maps peer_url → PeerSync pid)
    └── PeerSync (per peer, Supervisor :one_for_one)
        ├── ShapeConsumer (shape=user_card)
        └── ShapeConsumer (shape=user_storage)
```

## Modules

### `Electric.Shapes`

Central registry of synced shapes and their Ecto schema modules.

| Shape          | Schema Module                  | Table          | Primary Key         | Hash Format |
| -------------- | ------------------------------ | -------------- | ------------------- | ----------- |
| `:user_card`   | `Chat.Data.Schemas.UserCard`   | `user_cards`   | `user_hash`         | `"u_" + 128 hex chars` |
| `:user_storage`| `Chat.Data.Schemas.UserStorage`| `user_storage` | `(user_hash, uuid)` | `user_hash: "u_" + 128 hex`, `sign_hash: "uss_" + 128 hex` |

### `Electric.PeerIdentifier`

Fetches the PostgreSQL `system_identifier` from a peer by querying `GET <peer_url>/electric/v1/system_identifier`.

- Returns `{:ok, system_identifier}` or `{:error, reason}`
- 5-second receive timeout
- Logs warnings on failure

### `Electric.PeerSync`

Supervisor started per discovered peer. On init:

1. Fetches `system_identifier` from the peer via `PeerIdentifier`
2. Starts one `ShapeConsumer` per shape defined in `Shapes.all()`
3. Strategy `:one_for_one` — each shape consumer is independent
4. If `system_identifier` fetch fails, stops with `{:shutdown, :no_system_identifier}`

Registered in `ElectricRegistry` by `peer_url`.

### `Electric.ShapeConsumer`

GenServer consuming one Electric shape from one peer.

- Creates `Electric.Client` pointing at `<peer_url>/electric/v1/shape`
- Streams with `live: true, replica: :full` using the Ecto schema module
- Runs the stream in a monitored `Task`
- Dispatches messages to self:
  - `ChangeMessage` (insert/update/delete) → forwards to `ShapeWriter`
  - `ResumeMessage` → saves to `OffsetStore`, resets backoff
  - `ControlMessage(:up_to_date)` → broadcasts `LiveStatus`
  - `ControlMessage(:must_refetch)` → clears offset, restarts stream from scratch
- On task exit: retries with exponential backoff (1s → 2s → 4s → ... → max 5min)
- On resume: passes saved `ResumeMessage` to `Electric.Client.stream/3`

### `Electric.ShapeWriter`

Writes incoming shape changes to local PostgreSQL.

| Shape / Op     | Strategy                                                       |
| -------------- | -------------------------------------------------------------- |
| user_card insert/update  | `Repo.insert(card, on_conflict: {:replace_all_except, [:user_hash]}, conflict_target: :user_hash)` |
| user_storage insert/update | `Repo.insert(storage, on_conflict: {:replace, [:value_b64]}, conflict_target: [:user_hash, :uuid])` |

Both shapes use soft-delete semantics: removal is represented as an UPDATE that sets `deleted_flag: true` (and bumps `owner_timestamp`). Electric emits `:insert`/`:update` ops only; `:delete` ops are not part of the sync contract.

- Uses `Chat.Db.repo()` for dynamic repo resolution
- Logs warnings on write failures but does not crash
- Bypasses PoP authentication — peer sync is a trusted internal operation

### `Electric.OffsetStore`

Persists `ResumeMessage` data to CubDB (`Chat.AdminDb`).

- Key: `{:electric_sync_offset, system_identifier, shape}`
- `save(system_identifier, shape, resume)` — stores resume message
- `load(system_identifier, shape)` → resume message or `nil`
- `delete(system_identifier)` — removes all shape offsets for a peer

### `Status.LiveStatus`

New status struct indicating the shape consumer is connected and receiving real-time updates. Carries a `since` monotonic timestamp.

## Peer Discovery

`LanDetection.on_lan/2` is extended with Electric peer probing alongside existing GraphQL probing.

### Electric Probe

```
GET http://<ip>:<peer_port>/electric/v1/user_card?offset=-1
```

- Success: HTTP 200 with `electric-handle` response header → register as Electric peer
- Uses `Req.get/2` with 3-second timeout
- Same port as the peer's HTTP server (discovered, not hardcoded)
- Scanned concurrently (`Task.async_stream`, max 1000 concurrency)

### Flow

1. Scan LAN subnet (existing logic)
2. For each IP, probe `/naive_api` (GraphQL) **and** `/electric/v1/user_card?offset=-1` (Electric)
3. Skip IPs already known as Electric peers
4. Call `NetworkSynchronization.add_electric_peer/1` for each discovered peer

### Manual peer via admin panel

When a GraphQL source is started via the admin panel (`start_source/1`), the base URL is derived from the GraphQL source URL and `add_electric_peer/1` is called automatically. When the source is stopped, `remove_electric_peer/1` is called to terminate the corresponding `PeerSync`.

Base URL derivation: `http://IP:PORT/naive_api` → `http://IP:PORT`

## API Endpoints

### `GET /electric/v1/system_identifier`

Exposed by `ChatWeb.SystemIdentifierController`. Returns the local PostgreSQL `system_identifier`.

- Queries `SELECT system_identifier FROM pg_control_system()`
- Response: `{"system_identifier": "<string>"}`
- Error: 500 with `{"error": "<reason>"}`

## Conflict Resolution

- **Last-write-wins** via `ON CONFLICT ... DO UPDATE` — consistent with Electric's log ordering
- **Replication loops**: Accepted as idempotent. Upserting identical data produces no new WAL entry, so Electric does not re-replicate unchanged rows.

## Error Handling

| Scenario                  | Behavior                                                     |
| ------------------------- | ------------------------------------------------------------ |
| Peer unreachable          | Task exits, retry with exponential backoff (1s → max 5min)   |
| Stream task exits         | GenServer schedules `:restart_stream` after backoff           |
| `must_refetch` control    | Clear saved offset, restart stream from scratch              |
| Write failure             | Log warning, continue processing stream                      |
| system_identifier failure | PeerSync stops with `{:shutdown, :no_system_identifier}`     |
| Stale `:DOWN` message     | Ignored (from previously cancelled tasks)                    |

## PubSub

Status changes broadcast on `"chat::NetworkSynchronization"` topic:

```elixir
{:admin, {:electric_sync_status, peer_url, shape, status}}
```

Where `status` is one of:
- `%SynchronizingStatus{}` — initial shape download or refetch in progress
- `%LiveStatus{}` — connected and receiving real-time updates
- `%ErrorStatus{}` — stream error with reason string

## Public API

Added to `Chat.NetworkSynchronization`:

- `add_electric_peer(peer_url)` — starts a `PeerSync` supervisor for the peer
- `remove_electric_peer(peer_url)` — terminates the peer's supervisor
- `list_electric_peers()` — returns list of registered peer URLs

## Admin UI

Electric sync status is displayed inline on each network source card in the admin panel (`NetworkSourceList` component).

### Status badges

Each card shows a row of per-shape badges below the GraphQL status section, visible only when Electric sync is active for that peer:

```
[ user_card  ✓ live ]  [ user_storage  ↻ syncing... ]
```

Badge states:

| Symbol | Meaning | Color |
| ------ | ------- | ----- |
| `✓ live` | Connected, receiving real-time updates | green |
| `↻ syncing...` | Initial snapshot download in progress | gray |
| `✗ err: <reason>` | Stream error, retrying with backoff | red |

Symbols are the primary indicator to ensure readability without color perception.

### Data flow

```
ShapeConsumer
  → PubSub {:electric_sync_status, peer_url, shape, status}
    → AdminPanelRouter
      → AdminPanel.send_electric_sync_update/4
        → send_update(NetworkSourceList, electric_status_update: ...)
          → NetworkSourceList.update/2 merges into electric_status assign
            → electric_status_for/2 correlates by base URL
              → electric_shape_badge renders per shape
```

Correlation between GraphQL source and Electric peer is done by matching the base URL (`scheme://host:port`) extracted from the source's `/naive_api` URL against the Electric `peer_url`.

## What Stays on GraphQL

Chat messages, dialogs, rooms, and other CubDB-stored data remain on the existing GraphQL sync path. Electric sync applies only to PostgreSQL-backed tables.

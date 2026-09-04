# Electric Network Sync

## Purpose

Synchronize PostgreSQL-backed data between BuckitUp LAN peers using Electric shape streaming. All shapes registered in [`Chat.Data.Shapes`](../../lib/chat/data/shapes.ex) with the `@syncable` designation are synced — currently 13 shapes covering user cards, user storage, dialog keys, dialog messages, reactions, receipts, files, file chunks, origins, reviews, review public passwords, review post rights, review revoke rights, and review lists. Complements the existing GraphQL/CubDB sync which handles CubDB-stored data.

## Architecture

### Sync Model

Each device runs an Electric-capable HTTP server. When a peer is discovered on the LAN, the local device opens long-polling Electric shape streams against the peer's `/electric/v1/shapes` endpoint. Incoming rows are written to local PostgreSQL via shape-specific behaviour callbacks.

```
Device A                                   Device B
┌────────────────┐                         ┌────────────────┐
│  PostgreSQL    │  Electric Shape HTTP    │  PostgreSQL    │
│  (13 syncable  │◄─────────────────────── │  (13 syncable  │
│   shapes)      │  GET /electric/v1/...   │   shapes)      │
│                │  (long-poll, offset)    │                │
└────────────────┘                         └────────────────┘
```

- Transport: `Electric.Client` (Elixir HTTP long-poll)
- Real-time: yes (live shape streaming with offset tracking)
- Resume: built-in via `ResumeMessage` persisted to CubDB
- Endpoint: `<peer_url>/electric/v1/shapes` with keepalive transport

### Peer Identification

Peers are identified by their PostgreSQL `system_identifier` — a unique 64-bit value generated at cluster init. This is more reliable than IP addresses in DHCP environments.

Each device exposes `GET /electric/v1/system_identifier` which returns `{"system_identifier": "<value>"}`. The identifier is fetched once when a peer connection is established and used as the key for offset storage.

### Supervision Tree

```
NetworkSynchronization.Supervisor  (strategy: :rest_for_one)
├── DynamicSupervisor           (Dynamic — existing GraphQL workers)
├── Registry                    (Registry — existing)
├── LanDetector                 (PeerDetection.LanDetector)
├── DeferredStore               (Electric.DeferredStore — ETS-backed deferred records)
├── DynamicSupervisor           (ElectricDynamic — manages PeerSync instances)
└── Registry                    (ElectricRegistry — maps peer_url → PeerSync pid)
    └── PeerSync (per peer, Supervisor :one_for_one)
        ├── ShapeConsumer (shape=user_card)
        ├── ShapeConsumer (shape=user_storage)
        ├── ShapeConsumer (shape=dialog_keys)
        ├── ...one per Shapes.sync_shape_names()
        └── ShapeConsumer (shape=review_list)
```

Source: [`Supervisor.init/1`](../../lib/chat/network_synchronization/supervisor.ex)

## Modules

### [`Chat.Data.Shapes`](../../lib/chat/data/shapes.ex)

Central registry of all shape behaviour modules. Each shape module implements the [`Chat.Data.Shapes.Shape`](../../lib/chat/data/shapes/shape.ex) behaviour.

Key functions:

- `all/0` — all 16 registered shapes (includes non-syncable candidates)
- `sync_shape_names/0` — names of the 13 `@syncable` shapes (excludes `@not_syncable` candidates)
- `by_name/1` — lookup shape module by atom name
- `by_schema/1` — lookup shape module by Ecto schema module

The `@not_syncable` shapes (review password/post-right/revoke-right candidates) are excluded from peer sync.

### [`Chat.Data.Shapes.Shape`](../../lib/chat/data/shapes/shape.ex) (behaviour)

Defines the callback pipeline used by both peer sync (ShapeWriter) and HTTP ingestion (ElectricController):

```
sync_required_parents/2  → [{shape, key}]     (parent dependencies)
sync_validate_parent/2   → :ok | {:reject, _}  (validate parent)
sync_derive_fields/1     → struct              (compute derived fields)
sync_persist/2           → {:ok, _} | {:error, _}  (write to DB)
sync_after_persist/3     → :ok                 (post-write hooks; opts include peer_url)
ingest_configure_writer/2 → Writer             (HTTP ingestion config)
```

Optional `persist:` macro generates standard insert/update logic with validation changesets and upsert functions.

### [`Electric.PeerIdentifier`](../../lib/chat/network_synchronization/electric/peer_identifier.ex)

Fetches the PostgreSQL `system_identifier` from a peer by querying `GET <peer_url>/electric/v1/system_identifier`.

- Returns `{:ok, system_identifier}` or `{:error, reason}`
- 5-second receive timeout (`Req.get` with `receive_timeout: 5_000`)
- Logs warnings on failure

### [`Electric.PeerSync`](../../lib/chat/network_synchronization/electric/peer_sync.ex)

Supervisor started per discovered peer. On init:

1. Fetches `system_identifier` from the peer via `PeerIdentifier`
2. Starts one `ShapeConsumer` per shape from `Shapes.sync_shape_names/0`
3. Strategy `:one_for_one` — each shape consumer is independent
4. If `system_identifier` fetch fails, stops with `{:shutdown, :no_system_identifier}`

Registered in `ElectricRegistry` by `peer_url`.

### [`Electric.ShapeConsumer`](../../lib/chat/network_synchronization/electric/shape_consumer.ex)

GenServer consuming one Electric shape from one peer.

- Creates `Electric.Client` pointing at `<peer_url>/electric/v1/shapes`
- Streams with `live: true, replica: :full` using the Ecto schema module
- Runs the stream in a monitored `Task` (via `Task.start/1`)
- State: `{peer_url, system_identifier, shape, task_info, backoff_ms, restart_ref}`
- Checks `Chat.Db.repo_ready?/0` before starting stream; schedules retry if repo unavailable
- Dispatches messages to self:
  - `ChangeMessage` (insert/update/delete) → forwards to `ShapeWriter.write/4` with `peer_url:` opt
  - `ResumeMessage` → saves to `OffsetStore`, resets backoff
  - `ControlMessage(:up_to_date)` → broadcasts `LiveStatus`
  - `ControlMessage(:must_refetch)` → cancels task, clears offset, purges deferred records for shape, restarts stream
- On task exit: clears offset for the specific shape, retries with exponential backoff (1s → 2s → 4s → ... → max 5min)
- On resume: passes saved `ResumeMessage` to `Electric.Client.stream/3`
- On write returning `{:error, :repo_not_available}`: cancels task, schedules retry with backoff

### [`Electric.ShapeWriter`](../../lib/chat/network_synchronization/electric/shape_writer.ex)

Writes incoming shape changes to local PostgreSQL via the Shape behaviour pipeline:

1. Looks up shape module via `Shapes.by_name/1`
2. Checks parent dependencies via `shape_mod.sync_required_parents/2`
3. If parents missing: defers the record via `DeferredStore.defer/5` (when `peer_url:` opt present)
4. If parents present: `sync_derive_fields/1` → `sync_persist/2` → `sync_after_persist/3`
5. After successful persist: checks `DeferredStore` for children waiting on this record and triggers redelivery

- Uses `Chat.Db.repo/0` for dynamic repo resolution
- Logs warnings on write failures but does not crash
- Rescues `RuntimeError` as `:repo_not_available` and `Postgrex.Error`

### [`Electric.DeferredStore`](../../lib/chat/network_synchronization/electric/deferred_store.ex)

ETS-backed GenServer that holds records whose parent shapes haven't arrived yet. Shared across all ShapeConsumers.

- Table: `:buckitup_deferred_records` (`:bag`, `:public`, `:named_table`)
- `defer/5` — stores a `DeferredRecord` keyed by each missing parent `{shape, key}`
- `check_children/2` — takes and returns all deferred records waiting on a given parent
- `trigger_redeliver/1` — spawns tasks (via `Chat.TaskSupervisor`) that re-fetch the specific record from the peer and replay through `ShapeWriter`
- `purge_peer/1` — removes all deferred records for a peer URL
- `purge_shape/2` — removes deferred records for a specific peer + shape
- TTL sweep: every 5 minutes, purges records older than 2 hours

Redelivery re-fetches the record from the peer via a one-shot `Electric.Client.stream/3` (with `live: false`) using an Ecto `where` query built from the primary key.

### [`Electric.DeferredRecord`](../../lib/chat/network_synchronization/electric/deferred_record.ex)

Struct representing a deferred record:

- `shape` — atom shape name
- `key` — primary key (keyword list from `Ecto.primary_key/1`)
- `operation` — `:insert` or `:update`
- `missing_parents` — list of `{parent_shape, parent_key}` tuples
- `peer_url` — source peer URL
- `deferred_at` — monotonic timestamp for TTL

### [`Electric.OffsetStore`](../../lib/chat/network_synchronization/electric/offset_store.ex)

Persists `ResumeMessage` data to CubDB (`Chat.AdminDb`).

- Key: `{:electric_sync_offset, system_identifier, shape}`
- `save(system_identifier, shape, resume)` — stores resume message
- `load(system_identifier, shape)` → resume message or `nil`
- `delete(system_identifier)` — removes all shape offsets for a peer (iterates `Shapes.sync_shape_names/0`)
- `delete(system_identifier, shape)` — removes offset for a specific shape

### `Status.LiveStatus`

Status struct indicating the shape consumer is connected and receiving real-time updates. Carries a `since` monotonic timestamp.

Source: [`live_status.ex`](../../lib/chat/network_synchronization/status/live_status.ex)

## Peer Discovery

[`LanDetection.on_lan/2`](../../lib/chat/network_synchronization/peer_detection/lan_detection.ex) runs Electric peer probing as a separate pass after GraphQL probing.

### Electric Probe

```
GET http://<ip>:<peer_port>/electric/v1/shapes?table=user_cards&offset=-1
```

- Success: HTTP 200 with `electric-handle` response header → register as Electric peer
- Uses `Req.get/2` with 3-second timeout, `retry: false`
- Same port as the peer's HTTP server (from `ChatWeb.Endpoint` config)
- Scanned concurrently (`Task.async_stream`, max 1000 concurrency)

### Flow

1. Scan LAN subnet (existing logic)
2. For each IP, probe `/naive_api` (GraphQL) first, then `/electric/v1/shapes?table=user_cards&offset=-1` (Electric) in a separate pass
3. Skip IPs already known as Electric peers (`list_electric_peers/0`)
4. Call `NetworkSynchronization.add_electric_peer/1` for each discovered peer

### Manual peer via admin panel

When a GraphQL source is started via the admin panel (`start_source/1`), the base URL is derived from the GraphQL source URL and `add_electric_peer/1` is called automatically. When the source is stopped, `remove_electric_peer/1` is called to terminate the corresponding `PeerSync` and purge its deferred records.

Base URL derivation: `http://IP:PORT/naive_api` → `http://IP:PORT`

Source: [`network_synchronization.ex`](../../lib/chat/network_synchronization/network_synchronization.ex) `start_source/1`, `stop_source/1`

## API Endpoints

### `GET /electric/v1/system_identifier`

Exposed by [`ChatWeb.SystemIdentifierController`](../../lib/chat_web/controllers/system_identifier_controller.ex). Returns the local PostgreSQL `system_identifier`.

- Queries `SELECT system_identifier FROM pg_control_system()` via `Ecto.Adapters.SQL.query/3` on `Chat.Db.repo/0`
- Response: `{"system_identifier": "<string>"}`
- Error: 500 with `{"error": "<reason>"}`

## Conflict Resolution

Conflict handling is delegated to each shape's `sync_persist/2` callback. Shapes using the `persist:` macro get changeset validation (insert and update) followed by a shape-specific upsert function. The shape behaviour validates incoming data against existing records before writing.

## Error Handling

| Scenario                  | Behavior                                                     |
| ------------------------- | ------------------------------------------------------------ |
| Peer unreachable          | Task exits, offset cleared, retry with exponential backoff (1s → max 5min) |
| Stream task exits         | Offset cleared for that shape, GenServer schedules `:restart_stream` after backoff |
| `must_refetch` control    | Cancel task, clear offset, purge deferred records for shape, restart stream |
| Write failure             | Log warning, continue processing stream                      |
| Repo not available        | Cancel task, broadcast `ErrorStatus`, schedule retry with backoff |
| system_identifier failure | PeerSync stops with `{:shutdown, :no_system_identifier}`     |
| Stale `:DOWN` message     | Ignored (from previously cancelled tasks)                    |
| Missing parent record     | Record deferred in ETS; redelivered when parent arrives (TTL: 2h) |

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

In [`Chat.NetworkSynchronization`](../../lib/chat/network_synchronization/network_synchronization.ex):

- `add_electric_peer(peer_url)` — starts a `PeerSync` supervisor for the peer; notifies `SyncSource` of connection
- `remove_electric_peer(peer_url)` — purges deferred records, notifies `SyncSource` of disconnection, terminates the peer's supervisor
- `list_electric_peers()` — returns list of registered peer URLs
- `init_electric_peers/0` — on startup, re-starts Electric peers for all started GraphQL sources

## Admin UI

Electric sync status is displayed inline on each network source card in the admin panel ([`NetworkSourceList`](../../lib/chat_web/live/main_live/admin/network_source_list.ex) component).

### Status badges

Each card shows a row of per-shape badges below the GraphQL status section, visible only when Electric sync is active for that peer:

```
[ user_card  ✓ live ]  [ user_storage  ↻ syncing... ]
```

Badge states:

| Symbol | Meaning | Color |
| ------ | ------- | ----- |
| `✓ live` | Connected, receiving real-time updates | green (`text-green-700`) |
| `↻ syncing...` | Initial snapshot download in progress | gray (`text-gray-500`) |
| `✗ err: <reason>` | Stream error, retrying with backoff | red (`text-red-700`) |

Symbols are the primary indicator to ensure readability without color perception.

### Data flow

```
ShapeConsumer
  → PubSub {:electric_sync_status, peer_url, shape, status}
    → AdminPanelRouter.info/2
      → AdminPanel.send_electric_sync_update/4
        → send_update(NetworkSourceList, electric_status_update: ...)
          → NetworkSourceList.update/2 merges into electric_status assign
            → electric_status_for/2 correlates by base URL
              → electric_shape_badge renders per shape
```

Correlation between GraphQL source and Electric peer is done by matching the base URL (`scheme://host:port`) extracted from the source's `/naive_api` URL against the Electric `peer_url`.

Source: [`admin_panel_router.ex`](../../lib/chat_web/live/main_live/page/admin_panel_router.ex), [`admin_panel.ex`](../../lib/chat_web/live/main_live/page/admin_panel.ex)

## What Stays on GraphQL

CubDB-stored data remains on the existing GraphQL sync path. Electric sync applies only to PostgreSQL-backed tables registered in `Chat.Data.Shapes` as `@syncable`.

# PQ Recovery Services

## Purpose

Community backup and recovery (`chat-frontend/docs/backup-recovery-overview.md`)
runs on a contract and three services:
- a **relayer** that pays gas for signed calls;
- an **indexer** with a read API and **notifications** that warn an owner of a
  recovery started on their secret;
- **custodian nodes** that hold the node half of each secret and release it
  only once the contract says the recovery is due.

Today these are TypeScript services in `Community-secret-sharing`:
- `backitup-recovery-backend`: NestJS on MongoDB, ~3,300 lines — the relayer,
  indexer, read API and notifications in one process;
- `backitup-node`: Express on a JSON file, ~900 lines.

They run on Railway. This requirement moves them onto our own servers, in
Elixir, inside the chat release. The split follows what each one may and may
not share with its copies elsewhere.

The request and response formats do not change. The SDK, its harness, the
demo and the client keep calling the same paths under a base URL, so each
service can be switched separately.

---

## Placement

| Service | Runs | Shares with other servers |
|---|---|---|
| Relayer, with an indexer for its own dispatches | **One per chain**, on a host we operate | Nothing |
| Indexer and read API | Every server with internet | Nothing — the chain is the shared state |
| Custodian node | Every server and device that opts in | **Nothing, ever** — § Nodes |
| Notifications | Every server with internet | Nothing in the first version — § Notifications |

### Mounting

Everything is served by the chat endpoint under `/recovery`, routed before the
router's catch-all `get "/*path"`:
- the relayer and read API at `/recovery/api/...`, so a client's relayer base
  URL is `https://<host>/recovery`;
- the node at `/recovery/node/...`, so a node is listed as
  `<id>@https://<host>/recovery/node`.

The paths below are relative to those bases. Configuration keeps the
TypeScript services' variables and their meaning, under a `RECOVERY_` prefix
where a name is taken (`PORT`, `NODE_ID`).

### Relayer — one, and why

The relayer holds a hot wallet, the dispatcher, and is the only writer of its
nonce (`backitup-recovery-backend` README: one instance). Two relayers on one
key break each other's nonces. It needs no user data, and it is not a trust
anchor: the contract checks every signature.

**It is a single point of failure until the client can do without it.** The
fallback — the relayer URL as configuration, and a client that signs and pays
its own gas — is in the client plan (`chat-frontend` plan §7.0), not in the
client. Until it ships, a relayer outage stops every recovery action,
including the owner's veto (`cancel-recovery`) during a timelock. That path
ships before this relayer is the only one.

- **Endpoints, unchanged:**
  - `POST /api/relayer/{add-secret, revoke-secret, reshare, set-recovery-policy,
    initiate-recovery, approve-recovery, approve-recovery-batch,
    cancel-recovery, invalidate-nonce, register-keys}`;
  - `GET /api/relayer/dispatches`.
- **What the port keeps.** Each item closes a defect the TypeScript relayer
  already had; the TypeScript tests (`test/relayer.test.ts`) port with it:
  - **One process owns the nonce.** A GenServer per dispatcher serializes
    submissions:
    - a local counter that tracks every nonce the chain has not yet seen;
    - nonce and fees read in one batch;
    - `eth_sendRawTransaction`, with a failure counted only when the node
      answers with a JSON-RPC error;
    - up to three re-signs on a collision.
  - **Claim before send.** An idempotency key per payload is claimed in a
    unique index before preflight and send. *N* parallel copies of one payload
    cost one transaction (audit R-H2); a vote already cast answers `409`.
  - **Dispatches reach a final state.** The relayer host's own indexer marks a
    dispatch processed when its event lands. A sweep fails a dispatch stuck
    past its deadline.
  - **Limits:** `MAX_GAS_PER_CALL` (default 6,500,000),
    `GAS_BUDGET_PER_HOUR`, `CALLS_PER_CALLER_PER_HOUR` and `CALLS_PER_HOUR`.
- **Restarts.** Claims and dispatches live in Postgres. The nonce is read from
  the chain's pending count at start. Hourly counters may reset, since they
  are abuse limits, not accounting.
- **Cold standby, not hot.** A second host may hold the key switched off. It
  is started by hand only after the first is confirmed down.

### Indexer and read API — on every server

Each server reads the contract's events itself and keeps them in its own
Postgres tables. Two servers that index the same blocks hold the same rows,
so nothing is replicated.

- **Endpoints, unchanged:**
  - `GET /api/secrets`, `/api/secrets/:id`, `/api/secrets/:id/guardians`;
  - `/api/secrets/:id/shares/:stealthAddress`, `/api/secrets/:id/can-decrypt`,
    `/api/secrets/:id/round-state`;
  - `/api/meta-address`, `/api/events`, `/api/health`.
- **The tables are local:** not Electric shapes, not in peer sync, not in
  `user_storage`. Per deployment: `CHAIN_ID`, `RPC_URL`,
  `SECRET_RECOVERY_ADDRESS`, `KEY_REGISTRY_ADDRESS`, `START_BLOCK`.
- **A device with no internet runs no indexer.** It has nothing to read.

---

## Nodes

A node holds one share of the node half of `S`. The node half alone reveals
nothing, and the friends' half alone reveals nothing. What the node plane
buys is a second, independent party that releases only to the recipient the
contract elected, after the timelock. That is worth exactly as much as the
nodes are independent of each other and of us.

### The rule: a node's shares never leave it

A share deposited with node A is stored by node A and by nothing else:
- not in an Electric shape;
- not in peer sync between devices;
- not in `user_storage`;
- not on a "backup" server.

A replicated node store turns every server into a holder of every node's
share, and the node threshold into a formality. Durability comes from the
threshold instead: a secret split *k*-of-*n* across nodes survives the loss of
*n − k* of them.

**Storage.**
- Shares go in a local Postgres table outside the Electric registry, each
  encrypted at rest under a node key.
- The node key and the node's id live in AdminDB, so a Postgres dump alone
  yields nothing.
- AdminDB is single-drive today (`pq_access_gating`, Open question 3), while
  Postgres replicates to the device's backup drive. A node restored from that
  drive has its shares but not the key, which is the node lost. The threshold
  covers that. Copying the key and id with the drive is part of the AdminDB
  backup question, not a reason to put the key beside the shares.

**The node id** is configured (`RECOVERY_NODE_ID`) and stored with the key. It
is not the server identity's `user_hash`: a node that loses its key loses its
shares anyway, but a node whose identity is rebuilt must still answer to the
id its depositors signed for.

### Endpoints, messages and gates, unchanged

`GET /health`, `POST /shares` and `POST /shares/:id/release` take the signed
messages of the SDK's `src/constants/messages.ts`:
- `Backitup node share deposit v2` and `… request v2`;
- the node id, a single-use nonce, a timestamp and, for a deposit, the share's
  digest.

**Every gate of the TypeScript node is part of the contract:**
- a timestamp older than the window, or in the future, is refused;
- a nonce is used once;
- a deposit is accepted only while the secret's round state is `None` or
  `Expired`;
- a deposit at a version below the stored one is `409`;
- a release only while `canDecrypt` holds for the requester, read from the
  chain at that moment;
- an unreachable chain is `503`, never "the secret does not exist";
- a pre-chain deposit is filed under its signer and promoted when the secret's
  real owner appears on chain.

The `backitup-node` tests port with it.

### Who runs nodes, and the limit of that

- **Hosts.** Every BuckitUp device can run the node module, and a device
  belongs to its owner. Our own servers run nodes too, never enough to meet a
  threshold alone: the client's default node set and threshold keep the nodes
  we host below the threshold. A node needs the internet to release, because
  a release reads `canDecrypt`. Without the internet it still holds.
- **Code.** Hosts are not the whole of independence: every node module runs
  code we ship. A compromised or compelled release could make every device's
  node hand over its shares at once, which meets any threshold. Counting hosts
  does not answer that. What does:
  - **No silent updates for the node module.** A device runs a new node
    version only after its owner accepts it. Releases are signed and
    reproducible, so an operator can check what they run.
  - **Code diversity in the default set.** The client's default node set
    includes nodes that do not run our release — the TypeScript node, run by
    another operator — enough that our release alone stays below the
    threshold.

---

## Notifications

An owner must hear of a recovery on their secret within the timelock, or the
veto decorates nothing. With a copy of the service on every server, the
question is how they hear it once.

### One event, one id

Every server sees the same on-chain event and names it the same way:

```
event_id = chainId ":" contract ":" secretId ":" round ":" type
type ∈ { RECOVERY_STARTED, QUORUM_REACHED }
```

All values are lowercase hex or decimal, so the string is equal on every
server.

### Only live rounds alert

An event alerts only while its round is still live at sending time: state
`Voting` or `TimeLock`, and `expiresAt` not passed. An indexer catching up
from `START_BLOCK`, or a device back online after days, re-reads old events
and sends nothing for rounds that are over. A false alarm on the veto path
trains owners to ignore the real one.

### In the app: one alert at any number of servers

Alerts for the app are derived from the index, not from subscriptions:
- `GET /api/alerts?wallet=&ts=&sig=` (proof by the owner key, as the current
  notifications read) returns one row per live `event_id` on secrets owned by
  `wallet`, with `chainId`, `contract`, `secretId`, `round`, `type`,
  `executeAfter` and `expiresAt`;
- every indexing server returns the same rows for the same blocks, whether or
  not the owner subscribed there;
- the client keys them by `event_id` and shows each once;
- the client also reads its own secrets' round state from the chain, so the
  alert does not depend on any server being up.

This replaces today's `GET /api/notifications?wallet=` for the app. That
endpoint returns one row per subscription and nothing on a server where the
owner has none.

### External channels: one sender per subscription

A subscription (Telegram, webhook; later e-mail, SMS) is held by the server
where the owner made it, and **only that server sends it**.

- Subscriptions are not replicated in this version. Another server never sees
  one, so it cannot send a duplicate.
- Telegram fixes this anyway: a bot token belongs to one server, and two
  servers cannot both poll one bot.
- The sent-log key is `event_id ":" subscription_id`, unique in Postgres, so
  one server never sends one event twice across restarts and re-indexing.
- **Redundancy is the owner's choice.** An owner who wants an alert to survive
  one server going down subscribes on two servers and gets two messages — on
  purpose.

### A BuckitUp channel

A third kind, `buckitup`, delivers the alert as an end-to-end dialog message
from the server's identity (the `SyncBot_<device_id>` card) to the owner's
`user_hash`.

- **Enrolment** binds the two halves of the owner. The wallet signs the
  subscription, as for any subscription. The chat identity makes the request,
  by the ingest PoP. The pair is stored with the subscription.
- **One sender, as for any subscription.** The message is an ordinary signed
  dialog row, and dialog sync carries it everywhere as one message.

### Later: failover without the owner

A lease per subscription can be added on top of this:
- the sender renews it;
- when it lapses, the next server in a deterministic order over server ids
  takes over;
- a replicated sent-log marks what was sent.

During a network split two servers may both send. For an alarm that is the
right failure. This needs subscriptions replicated, which the first version
avoids.

---

## The Elixir port

Each service is a supervised application inside the chat release, started by
configuration. A server without the relayer key does not start the relayer; a
device that opts out of custody does not start the node.

- **Ethereum:**
  - `curvy` (already a dependency) for secp256k1 signing and recovery;
  - Keccak-256 and ABI encoding from `ex_abi` and `ex_keccak`, or the `ethers`
    package that bundles them. Before choosing, check that their native code
    builds for the Raspberry Pi target (aarch64), or keep to pure-Elixir
    implementations;
  - JSON-RPC over `req` (already a dependency).
- **Storage:** Postgres replaces MongoDB. The relayer's claims and dispatches,
  the indexer's events and projections, and the subscriptions and sent-log are
  local tables. The node store is as § Nodes says.

## Acceptance

- **Relayer and nodes: the SDK harness, 10/10.** The harness
  (`backitup-secret-recovery-sdk/harness/run.mjs`) drives only the relayer
  and the nodes; it reads the chain itself.
  - Run it against the OP Mainnet test deployment: `CHAIN_ID=10`, an OP
    `RPC_URL`, `SECRET_RECOVERY_ADDRESS=0x45907bD5636CCECE1819fCd6433DEC71C78F3BB3`,
    `KEY_REGISTRY_ADDRESS=0x8364c4550CA2171A9bB2277B74C8B73ae2eBF21c`, start
    block 157813997.
  - `NODES` lists six nodes: scenarios 4 and 5 need six and are skipped
    otherwise.
  - First with six Elixir nodes and the TypeScript relayer, then with the
    Elixir relayer.
- **Indexer and read API: parity.** After a harness run, every read endpoint
  returns the same JSON from the Elixir and the TypeScript indexer for every
  secret the run created.
- **The rest:**
  - two Elixir servers indexing one contract return the same `/api/alerts`
    for an owner subscribed on neither;
  - one subscription on server A, A and B both running: one Telegram message
    per live event, and none for an event whose round has closed;
  - a node's share table appears in no Electric shape and no sync
    configuration (a test checks the registry and the sync setup);
  - each node gate of § Nodes refuses what it should (the ported tests);
  - a relayer restart in the middle of a batch leaves no nonce gap and no
    duplicate transaction.

## Migration

State moves with each service; nothing is re-created empty.

1. **Names first.** Give every service a name under our domain (e.g.
   `node-a.buckitup.xyz`, `relay.buckitup.xyz`), pointed at Railway for now.
   Clients and node lists use these names from then on, so no later move
   changes a URL.
2. **The TypeScript services on our host.** Copy each node's `DATA_FILE` under
   its own `NODE_ID`, and the MongoDB subscriptions and alert history, then
   move the names. Railway goes once the names point here.
3. **Nodes to Elixir, one at a time, with their shares.** The Elixir node
   imports the TypeScript node's `DATA_FILE` — promoted shares and pending
   claims — under the same id and name. No owner needs to reshare.
4. **Indexer, read API and notifications on every server.** Existing
   subscriptions, imported from MongoDB, go to the server that becomes their
   sender. Owners lose no channel.
5. **The relayer last.** One process with one key: stop the TypeScript one,
   then start the Elixir one, with the dispatch table imported.

## Status

Proposed.

## Open questions

1. **The relayer's host:** buckitup.xyz, or a separate machine, so a chat
   outage does not stop recovery transactions? Either way the client's
   own-gas path (§ Relayer) is what removes the single point of failure.
2. **Node operator policy:** how many of the default nodes we may host and
   ship code for, and who runs the nodes that do not run our release.
3. **Shares on a device that is wiped or sold:** the threshold covers loss,
   but the owner should be told which secrets lose a node. That needs the
   device to know its depositors, which today it knows only as wallet
   addresses.

## References

- `chat-frontend/docs/backup-recovery-plan.md` — phases, and the client work
  these services serve.
- PQ TURN relay (`pq_turn_relay.proposed.md`, in review) — the other service
  on the same host, behind the same PoP.
- [PQ access gating](pq_access_gating.in_progress.md) — the server identity
  and AdminDB that the node module uses.

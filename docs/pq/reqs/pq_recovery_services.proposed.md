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

They run on Railway. This requirement moves them to Elixir:
- the relayer as its own release on its own machine;
- the indexer, read API and notifications inside the chat release on every
  server;
- the node as its own release beside it (§ Who runs nodes).

The split follows what each one may and may not share with its copies
elsewhere. The relayer, indexer and read API keep their request and response
formats; the node protocol gains four changes (§ Nodes).

---

## Placement

| Service | Runs | Shares with other servers |
|---|---|---|
| Relayer, with an indexer for its own dispatches | **One per chain**, on its own machine (Railway), apart from the chat servers | Nothing |
| Indexer and read API | Every server with internet | Nothing — the chain is the shared state |
| Custodian node | Every server and device that opts in | **Nothing, ever** — § Nodes |
| Notifications | Every server with internet | Nothing in the first version — § Notifications |

### Mounting

Three releases, one URL scheme:
- **the relayer**, its own release on its own machine (Railway), with only its
  dispatch indexer: a chat outage does not stop recovery transactions. Its
  base URL is `https://<relay host>/recovery`;
- **the indexer, read API and notifications** in the chat release, under
  `/recovery/api/...`, routed before the router's catch-all `get "/*path"`;
- **the node**, its own release on the same host, reached through the host's
  reverse proxy at `/recovery/node/...`. A node is listed as
  `<id>@https://<host>/recovery/node`.

The paths below are relative to those bases. Configuration keeps the
TypeScript services' variables and their meaning, under a `RECOVERY_` prefix
where a name is taken (`PORT`).

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

**The node id is derived from the node key**: `n_` + lowercase hex of the first
16 bytes of `SHA3-256(node public key)`. The key is a secp256k1 key the node
generates and keeps in AdminDB with the share-encryption key. Nobody can claim
another node's id without its key, and a node that loses its key loses its id
together with its shares — the threshold covers both.

### Endpoints, messages and gates

The protocol is the TypeScript node's v2 with four changes, which make it v3:

- **`GET /info`** returns the node's descriptor (§ Choosing nodes).
- **`GET /shares/:id`** answers `{version}` while the node holds a promoted
  share for `id`, and `404` otherwise. Who holds a share of a public secret id
  is not secret, and the owner's client needs it to see a holding lost to a
  wipe (§ Choosing nodes).
- **A release is encrypted to the requester.** The node recovers the public
  key from the request's signature, checks that its address is the candidate
  for whom `canDecrypt` holds, and returns the share as ECIES to that key —
  the SDK's ECIES. A signed request relayed to the node by anyone else yields
  that relay nothing. Overview §4 already says it: nodes encrypt their share to
  the ephemeral key.
- **Messages name the key-derived id.** The SDK's
  `Backitup node share deposit v2` and `… request v2` become `… v3`, otherwise
  unchanged: the node id, a single-use nonce, a timestamp and, for a deposit,
  the share's digest.

**Every gate of the TypeScript node stays part of the contract:**
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

### Who runs nodes

Every BuckitUp device can run the node module, and a device belongs to its
owner. Our own servers run nodes too. A node needs the internet to release,
because a release reads `canDecrypt`. Without the internet it still holds.

Two different risks bound what a node set is worth, and they have different
answers.

**Who holds the disks.** Shares sit on the disks of whoever hosts the node. A
breach of that host, a compelled operator or a dishonest admin reads them
directly, at once, silently, and for every secret already deposited — no code
change needed. The answer is that no single operator holds a threshold of a
secret's nodes (§ Choosing nodes).

That answer counts operators, not hosting providers. Nodes of different
operators on one cloud provider share that provider's reach, and nothing a
node publishes proves where it runs. The default set spreads across
providers; an owner choosing nodes should too.

**Who ships the code.** Every node runs code we release. A malicious release,
once accepted, reads everything its node holds. What limits that:
- **The node module is released and updated on its own, never as part of a
  chat update.** It is a separate release with its own version, signed and
  reproducible, so an operator can check what they run.
- **A node runs a new version only after its operator accepts it.** Our own
  servers included: no automatic node updates.
- **Rollouts are staged**, so a release reaches nodes over days, not at once.

With every node on our code, this is the remaining trust in us: a compromised
signing key, and enough operators accepting a bad release before it is caught.
Staging and reproducibility make that slow and visible. They do not make it
impossible.

### Choosing nodes

The owner chooses which nodes hold a secret's node half. The client offers a
default set and checks any choice.

**A node says who runs it.** `GET /info` returns a descriptor:
- the node id, its URL, the chain and the contract it serves, and an
  `issued_at`;
- the node's signature over these, by the node key. The id is derived from
  that key, so the descriptor is bound to the node;
- the operator's endorsement: their `user_hash` and an ML-DSA-87 signature
  over the same fields, made once from the owner UI by the device owner of
  `pq_access_gating`. The client verifies it under the `sign_pkey` of the
  operator's verified card.

Encoding: the signed bytes are the UTF-8 of
`"buckitup/recovery-node/v1\n" || id || "\n" || url || "\n" || chain || "\n" || contract || "\n" || issued_at`.

A newer `issued_at` replaces an older descriptor, so a device that changes
hands gets its new owner's. A descriptor whose chain or contract is not the
secret's deployment is not offered. Descriptors are public metadata: the
client gathers them from the nodes it knows (the default list, its contacts'
devices, a URL typed in), and they may sync like any public record. Shares do
not (§ The rule). A node without a valid descriptor is not offered.

**The rules the client applies:**
- **Count operators, not nodes.** Three nodes of one operator are one party.
  The client refuses a set in which one operator holds a threshold of the
  nodes.
- **BuckitUp is one operator.** Every node we run is endorsed by one published
  BuckitUp identity, pinned in the client. "Count operators" therefore keeps
  our nodes below the threshold of any set, default or chosen.
- **A node's operator is never a guardian of the same secret.** One person
  holding both a guardian share and node shares collapses the two planes the
  scheme splits. The client compares the operators with the guardians it
  invited (the `user_hash` behind each accepted invitation) and refuses the
  overlap.
- **A spare.** The client suggests one (3 of 5 rather than 3 of 3).
- **Holdings are watched.** The client asks each node `GET /shares/:id`
  periodically, so a node that lost the share shows as lost even if it is up.
  When the losses eat into the spare, it prompts a reshare.
- **The set travels with the shares,** committed. `node_set` rides in
  `recovery_share` and comes back in `recovery_share_return`, and its hash is
  in `split_root` (`pq_recovery_shares` § Re-issuing). A recovering device
  verifies the set against the root before it contacts any node. Node URLs are
  stable names, or a moved device breaks every recovery that lists it.

What the checks cannot see is one person behind two accounts. They stop honest
mistakes; whom to trust stays the owner's judgement.

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

- **The relayer** is its own release, with its dispatch indexer, deployed on
  its own machine.
- **The indexer, read API and notifications** are supervised applications in
  the chat release, started by configuration.
- **The node** is its own release, updated only with its operator's consent
  (§ Who runs nodes). A device that opts out of custody does not run it.

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
  - a release request relayed by a third party yields it only ciphertext,
    which the candidate's key opens;
  - `/info` verifies under the node key and the operator's card, and a node
    serving another contract is not offered;
  - `GET /shares/:id` reports a wiped node as not holding;
  - a relayer restart in the middle of a batch leaves no nonce gap and no
    duplicate transaction.

## Migration

Node protocol v3 is a clean break. What the TypeScript nodes hold today are
test deposits on test deployments, and none of it is carried over: backups are
made again on v3.

1. **Names first.** Give every service a name under our domain (e.g.
   `node-a.buckitup.xyz`, `relay.buckitup.xyz`), pointed at its current host.
   Clients and node lists use these names from then on, so no later move
   changes a URL.
2. **The TypeScript backend stays on Railway as it is**, relayer, indexer and
   notifications together: it is one process with one key, and it is not
   split.
3. **Node protocol v3** in the SDK (messages, ECIES release, `/info`), the
   harness, and the Elixir node release. Elixir nodes go up on our servers and
   operators' devices; the TypeScript nodes are retired.
4. **Indexer, read API and notifications** in the chat release on every
   server. The TypeScript backend's notifications are switched off at the same
   moment: its Telegram token removed and its subscriptions deleted, so no
   event is sent twice.
5. **The relayer, on Railway.** Stop the TypeScript backend, then start the
   Elixir relayer release in its place.

## Status

Proposed.

## Open questions

1. **The default node set:** which operators besides us are in it, and its
   threshold. Until there are enough of them, no default set satisfies
   "count operators", and the client's simple backup screen has no default.
2. **The BuckitUp operator identity** that endorses our nodes: which account,
   and where its key lives.
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

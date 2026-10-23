# PQ Partner Venue Messaging

A partner platform runs its own BuckitUp server and lets its users write
privately to the venues it lists. YourTake is the first partner; nothing here
is specific to it.

Status: proposed. Every statement about current behaviour was checked against
`origin/main` at c2d4a77e (backend) and bc20acf (frontend); code references
are given where a reader might doubt it.

---

## Decisions

| # | Decision |
|---|---|
| D1 | The partner runs an **unmodified** BuckitUp server release on a domain of its own. No fork, no partner-specific server code. |
| D2 | The partner's servers sync only with each other. Sync with BuckitUp's servers is out of scope. |
| D3 | The partner owns venues as a product: listings, screens, one-time codes, visit checks, public reviews, its web UI for guests and for venue owners. |
| D4 | BuckitUp owns identities and the encrypted messages: the protocol, the server, and a client library the partner's web UI is built on. |
| D5 | Guests and venue owners use the partner's UI on the partner's domain. Their keys live in a vault on that domain. |
| D6 | Signing in on the partner's site with a key (R-7) uses that same-domain identity. Signing in with a key held by BuckitUp's own app on another domain is a separate project and needs PoP v1 (`pq_pop_binding.proposed.md`, branch `docs/pop-binding`); it is out of scope here. |

---

## Roles and identities

Every identity below is a `user_cards` row with its own ML-DSA-87, ML-KEM-1024
and secp256k1 keys ([pq_user.done.md](pq_user.done.md)).

| Role | What it is | Where its secret keys live |
|---|---|---|
| **Server owner** (O) | The partner's administrator account. Root of the server's trust chain. | The administrator's vault, partner domain |
| **Venue owner** (VO) | A person who manages one or more venues | VO's vault, partner domain |
| **Venue** (V) | An origin: a separate identity per venue ([reviews/pq_origin.done.md](reviews/pq_origin.done.md)). Guests write to it; it replies. | VO's User Storage, readable on every device of VO (§ Venue keys) |
| **Partner bot** (B) | The partner backend's identity. Admits guests by vouching for them. | The partner's backend |
| **Guest** (G) | A visitor who scanned a code | G's vault, partner domain |

---

## Server operation

### Device id

Scopes name the server as `device.<id>`. On a server `<id>` is
`Server_<host>`, with dots replaced by `_` (`lib/chat/device_id/default.ex`):
`Server_chat_partner_example` for `chat.partner.example`. A client reads it
from `GET /electric/v1/device_identity`, together with the owner (`admin`)
and the SyncBot.

### First owner

The first `user_cards` row written over HTTP ingest makes its user the server
owner (`lib/chat/pq/owner_bootstrap.ex`, called from
`ElectricController`). Peer sync never does. Nothing resets it short of
deleting `:pq_admin` from AdminDb on the server.

Procedure for a new server:
1. Deploy with the HTTP port reachable only by the administrator (firewall or
   bind address), and not by the partner's other servers: a peer that connects
   pushes its SyncBot card over HTTP ingest, and on a server without an owner
   that card is taken as the owner's.
2. The administrator signs in to the partner's UI pointed at this server; the
   card it publishes makes them the owner.
3. Check `GET /electric/v1/device_identity`: `admin.user_hash` is theirs.
4. Open the server to the public.

### Access mode

| Mode | Writes | Reads |
|---|---|---|
| `open` (default) | Anyone | Anyone |
| `guarded` | Need a vouch chain from O for `device.<id>.storage.write.<shape>` | Anyone |
| `trust` | As `guarded` | Need a read session per shape: a vouch chain for `device.<id>.storage.read.<shape>` (`user_cards`, `vouch_tokens` stay open) |

The mode is changed on `/electric/admin_sandbox` by O or an identity vouched
for `device.<id>.admin`, or from a console with
`Chat.AdminDb.put(:pq_gate_mode, :guarded)`. No HTTP API reports the mode.

**Production runs `guarded`.** `open` lets anyone write any row and is for a
closed pilot only. `trust` adds per-shape read sessions; it hides metadata from
anonymous readers, and notifications (§ Notifications) then need a vouched
reader.

The sandboxes (`/electric/*_sandbox`) are development tools: a production
server does not expose them, and the mode is then set from the console.

### Cross-origin access

CORS is `origin: "*"` on `/electric/v1/*` and exposes the `electric-*` headers,
so a browser on another domain talks to the server directly over HTTPS.
`x-challenge*` response headers are not exposed: a client gets each challenge
from `GET /electric/v1/challenge`. The comment in `router.ex` saying web
clients must proxy predates commit a6fe199d and no longer holds.

---

## Access model

Checked against `lib/chat/pq/write_gate.ex`, `lib/chat/data/vouch_token.ex`
and `test/chat/data/vouch_token/chain_distance_test.exs`.

### Scopes each role needs in `guarded`

| Identity | Scopes | For |
|---|---|---|
| B | `device.<id>.storage.write.dialog_keys`, `device.<id>.storage.write.dialog_messages` | passing them on to guests |
| V | `device.<id>.storage.write.origin`, `.dialog_keys`, `.dialog_messages` | creating the venue, replying |
| VO | `device.<id>.storage.write.user_storage` | keeping venue keys (§ Venue keys) |
| G | `device.<id>.storage.write.dialog_keys`, `.dialog_messages` | writing to a venue |

`user_cards` and `vouch_tokens` writes are not gated. Versions of a message
are written with it and need no scope of their own. Reactions and receipts
need `.dialog_message_reactions` / `.dialog_message_receipts` if the UI uses
them; a vouch for `device.<id>.storage.write` covers every shape.

O vouches for B, V and VO. B vouches for G.

### What a vouch grants, exactly

- **Anyone can issue a vouch.** Writing a `vouch_tokens` row needs only the
  issuer's key proof; authority is checked when a write is evaluated, by
  walking the chain from O (depth ≤ 7 by default).
- **A suffix does not narrow a grant.** A vouch for
  `device.<id>.storage.write.dialog_messages.<code>` satisfies
  `device.<id>.storage.write.dialog_messages`. A suffix only makes each row
  distinct, so a guest's grant can carry the code it came from.
- **A grant covers every dialog on the server.** Neither scopes nor dialog
  validation tie a writer to a peer: a guest admitted for venue V can also
  write to any other user of the server.
- **Retraction** is a row with `deleted_flag = true` from the same issuer at
  an equal or wider scope, with a newer `owner_timestamp`. It takes effect on
  the subject's next write.
  - B retracts B → G; O retracting O → B cuts off every guest B admitted.
  - A tombstone from O to G at the scope blocks G on every path.
  - A read session already issued lasts its 5 minutes.

The partner's server serves only the partner's users, so the wide grant is
accepted: the partner moderates and retracts. Restricting a guest to one
venue needs a peer-scoped grant in the backend; that is not part of this
requirement.

---

## Flows

### 1. Venue creation (venue owner, partner UI)

1. Generate the venue's keys: ML-DSA-87, ML-KEM-1024 and a secp256k1 contact
   key.
2. Ingest V's `user_cards` row, signed by V, key proof by V.
3. Ingest the `origins` row:
   - `origin_hash` = V's `user_hash`, `owner_hash` = VO's;
   - `owner_cert` = ML-DSA-87 by VO over the raw bytes of V's `sign_pkey`;
   - `name`, `moderation_mode`, `deleted_flag = false`, `owner_timestamp`;
   - `sign_b64` by V; `sign_hash` = `"ors_" + hex(SHA3-512(sign_b64))`, sent by the client;
   - key proof by V; V must hold `storage.write.origin` in `guarded`.
4. Store V's secret keys in VO's User Storage (§ Venue keys).

Later `origins` updates are signed by VO or V, with a key proof by VO, and
are refused while reviews await moderation.

The partner records `venue ↔ origin_hash` on its side.

### 2. A guest is admitted (scan of a one-time code)

1. G opens the partner's page from the code. The page creates G's identity
   or opens the existing one from G's vault, and ingests G's `user_cards` row
   if the server lacks it.
2. The page proves G's key to the partner backend: it signs a challenge the
   backend issued, under a purpose the partner defines, and the backend
   verifies it against G's `sign_pkey`.
3. The partner backend checks and spends the code, then B writes two
   `vouch_tokens` rows for G:
   `device.<id>.storage.write.dialog_keys.<code-id>` and
   `device.<id>.storage.write.dialog_messages.<code-id>`.
4. The partner records `code ↔ user_hash` and never vouches twice for one code.

B's rows are canonical BuckitUp rows: the partner backend signs them with
ML-DSA-87 (pure, empty context), builds the payload per
[02_integrity.md](../invariants/02_integrity.md), and proves B's key on
ingest. A backend in Go can use `cloudflare/circl`; the conformance vectors in
`test/fixtures/pq_conformance_vectors.json` check it.

### 3. Guest writes to the venue

A dialog between G and V ([pq_dialogs.done.md](pq_dialogs.done.md)):
1. `dialog_hash` from the two `user_hash` values.
2. G's `dialog_keys` row: G's `sender_msg_key` wrapped to V's `crypt_pkey`.
3. `dialog_messages` rows encrypted under G's `sender_msg_key`.

Nothing is venue-specific on the server: `to_origin` is a dialog whose peer is
V.

### 4. The venue owner reads and replies (partner UI)

1. VO signs in; the UI loads V's keys from VO's User Storage.
2. The UI reads `dialog_keys` where `peer_hash = V`, unwraps each guest's
   key with V's `crypt_skey`, and reads `dialog_messages` by `dialog_hash`.
3. Replies are written as V: V's own `dialog_keys` row to G, then messages,
   with key proofs by V.

The UI holds two identities at once, VO and V, and signs each request with
the identity the rows belong to.

### 5. Notifications

No server change. The partner backend subscribes, live, to
- `dialog_keys` where `peer_hash = '<V>'`: a new dialog with V;
- `dialog_messages` where `dialog_hash IN (...)`: a new message in one.

Both are readable anonymously in `open` and `guarded`. It learns sender,
dialog, size and time (`message_id` is a UUIDv7), never content. In `trust`
it reads as B, with read sessions renewed every 5 minutes, and B needs
`device.<id>.storage.read.dialog_keys` and `.dialog_messages`.

### 6. Removing a guest

B retracts its vouches for G; G can no longer write. Existing rows stay.

### 7. Erasure on request

Done by the operator on the partner's database:
- deleting a `user_cards` row removes the rows that reference it through
  `ON DELETE CASCADE`;
- message content is ciphertext under keys only the participants hold;
- an erased venue's dialogs become unreadable once its keys are deleted from
  VO's User Storage.

Whether every table referencing `user_cards` cascades, and whether a
`REVOKE DELETE` on the application role blocks a cascade, is to be checked on
a test server before this is relied on.

---

## Venue keys

V's secret keys live in VO's User Storage, so every device VO signs in on
can act as V. A venue is an owned subaccount of its owner
([pq_subaccounts.proposed.md](pq_subaccounts.proposed.md), branch
`docs/subaccounts`); a partner's client keeps the venues its users own and
nothing more of that model.

- **Slot:** a named JSON slot `origins` in VO's User Storage, one top-level
  key per venue so that two devices adding venues at once merge:
  ```json
  { "<origin_hash>": { "name": "…", "sign_skey": "<b64>", "crypt_skey": "<b64>",
                       "contact_skey": "<hex>",
                       "sign_pkey": "<b64>", "crypt_pkey": "<b64>" } }
  ```
- **Encryption and addressing:** as every User Storage slot of the frontend
  (`src/lib/data/slots.ts`, `src/lib/pq/slotId.ts`): the root record at a uuid
  derived from VO's `crypt_skey` maps slot names to random uuids; values are
  AES-256-GCM under a key derived from VO's `crypt_skey`.
- **Removing a venue:** drop its key from the slot. User Storage keeps
  versions, so erasure also needs the operator step of Flow 7.

A device that has VO's keys (device link, backup, recovery) has V's.

---

## Dialog key derivation

`sender_msg_key` is derived as [pq_dialogs.done.md § Key derivation](pq_dialogs.done.md)
gives it: `IKM = sign_skey || crypt_skey || peer_user_hash`, salt
`buckitup/dialog-mk/v1`. The client library and the BuckitUp frontend use this
derivation and no other key: one identity used from two clients derives the
same key for its own messages.

---

## Client library

`@buckitup/pq-client`: the protocol without Vue, Pinia or TanStack. BuckitUp's
frontend moves onto it, so there is one implementation.

- **Where:** a package in `Buckitup-chat/chat-frontend` (`packages/pq-client`),
  next to the app that uses it.
- **Published** to the public npm registry as `@buckitup/pq-client`.
- **Licence:** GPLv3, as the repository. On the usual reading of GPLv3, a web
  UI that bundles the library and is served to users is released under GPLv3
  as well. The partner has confirmed this suits it.

| Module | Contents |
|---|---|
| `identity` | key generation; `user_cards` row; certificates; `user_hash` |
| `vault` | secret keys at rest under a passkey's WebAuthn PRF output; several identities per session |
| `rows` | canonical payload, signing, verification, base64 padding rules |
| `transport` | challenge; `ingest` / `ingest_each` with key proof; shape reads, live; read sessions; error mapping |
| `dialogs` | `dialog_hash`; `sender_msg_key`; key wrap and unwrap; content encryption; messages, versions, `sign_hash`; row verification |
| `origins` | venue creation and update; `origin_settings` |
| `vouch` | issue and retract |
| `storage` | User Storage slots, JSON merge, venue keys |

- Server base URL is a parameter.
- Errors are typed: a refused gate, a stale `owner_timestamp`, a missing
  parent row and a transport failure are distinct.
- Golden vectors from the backend's conformance file are part of its tests.
- Semver; a protocol change is a major version and is announced to partners.
- The vault needs a passkey with the WebAuthn PRF extension. Which devices
  have it is measured with the probe page `/app/sandbox/prf-probe/index.html`
  of BuckitUp's client; the same table holds for the partner's users.

---

## Out of scope

- Restricting a guest to one venue (needs peer-scoped grants in the backend).
- Staff access to a venue. Delegating a venue hands its full keys to a staff
  member and happens in BuckitUp's own client
  ([pq_subaccounts.proposed.md](pq_subaccounts.proposed.md) § Delegation); a
  partner's client does not delegate.
- Signing in on a partner site with a key held by BuckitUp's own app (D6).
- Sync between a partner's servers and BuckitUp's.
- The partner's screens, codes and their protocol: `pq_review_mvp_qr_flow`
  Phases 1–2 do not apply to a partner deployment.

---

## Phases

| Phase | BuckitUp | Partner | Done when |
|---|---|---|---|
| **0. Ground** | Backend: a SyncBot card never becomes the owner; an older `vouch_tokens` row from a peer never replaces a newer one; sandboxes are not exposed on production servers. Frontend: `sender_msg_key` per `pq_dialogs` (no `evm_skey`). Correct `pq_user_storage.done.md` (paths, injector), the `router.ex` CORS comment, `pq_origin.done.md`. Publish an external-client guide. | Deploy a server on its domain; first owner per § First owner; `guarded`. | Partner's test client ingests a signed `user_cards` row and reads it back from a shape |
| **1. Library** | Extract `@buckitup/pq-client`; frontend on it; multi-identity vault | Build its UI on pre-releases | Library passes the conformance vectors; frontend tests green on it |
| **2. Venue messaging** | Venue creation, venue keys slot in the library; support | B, guest admission, guest and owner UI, notifications by shape | On the partner's test server: VO creates V; G scans a code, is vouched, writes; VO reads and replies from a second device; the partner backend is notified without content; retracting B → G stops G |
| **3. Sign-in by key (R-7)** | Support | Sign-in on its site with the same-domain identity | A guest signs in with the key alone |

---

## Open questions

1. Should the library ship before the partner starts on its UI, or alongside?
2. Erasure: confirm cascade behaviour on a test server (Flow 7).

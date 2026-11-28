# PQ Subaccounts

One person, several identities. The person signs in once, to their **master**
account, and acts as any identity of their **set** without another passkey.
This requirement sets the model and the decisions taken so far.

Status: proposed. The per-identity session exists in the frontend for notes
([pq_notes_to_self.proposed.md](pq_notes_to_self.proposed.md)); persona
derivations and server-aware device-link codes are in `@buckitup/pq-client`
1.2.0 ([`src/personas.ts`](https://github.com/Buckitup-chat/pq-library/blob/a3339a657dc8df5d8ad15b6d77e0bf2006847b31/src/personas.ts),
[`src/deviceLink.ts`](https://github.com/Buckitup-chat/pq-library/blob/a3339a657dc8df5d8ad15b6d77e0bf2006847b31/src/deviceLink.ts)).
The client side is specified in `chat-frontend` `docs/task-subaccounts-client.md`.

---

## Terms

| Term | Meaning |
|---|---|
| **Identity** | A `user_cards` row: ML-DSA-87, ML-KEM-1024 and secp256k1 keys, `user_hash` from `sign_pkey` ([pq_user.done.md](pq_user.done.md)). Not bound to a server: the same identity can be published on any. |
| **Master** | The account the device's passkey opens. A per-device fact: each device opens one master, and two devices of one person may open different ones. |
| **Persona** | An identity derived from an account's keys and an index. Its account can always derive it again; no secret key of a persona is stored. |
| **Added account** | An existing account whose full keys are kept in another account's keyring. |
| **Keyring** | A User Storage slot of an account with the full keys of the accounts added to it. |
| **The person's set** | The master, its personas, its keyring entries, and recursively the personas and keyrings of every account in it. |
| **Activate** | Act as an identity of the set: sign its rows and key proofs, read as it. |

---

## Use cases

### U1. Several identities in one app

A person keeps separate identities — for work, for an anonymous circle, for
a partner's service — and wants to switch between them in one app, with one
passkey, while contacts and servers see unrelated people.

### U2. Gathering accounts from devices, domains and backups

A person has accounts on other devices, on other domains (each domain has its
own vault and passkey), and in backup files. They add them to one account
and use them from there.

### U3. Notes to self — a derived identity

Notes are dialogs of a hidden identity derived from the account's keys, so
the server cannot tell they are notes or whose they are
([pq_notes_to_self.proposed.md](pq_notes_to_self.proposed.md)). It is the
first user of the per-identity session.

### U4. Delegating a venue to staff (later)

The review specs intend a venue identity to be "delegated to an employee
without exposing the owner's personal identity" ([reviews/pq_origin.done.md](reviews/pq_origin.done.md)).
A staff member needs the venue's secret keys, not only rights: reading a
review decrypts `review_post_right` with the venue's ML-KEM key, and replying
to a guest unwraps the dialog key with it. Vouch scopes grant writes on the
server; they cannot grant reading ciphertext. See § Delegation.

### Venues

Venues are not managed by BuckitUp's client. A partner runs its own server
on its domain with its own interface; the venue owner's client keeps the
venues' keys in the owner's `origins` slot through `@buckitup/pq-client`
([pq_partner_venue_messaging.proposed.md](pq_partner_venue_messaging.proposed.md)
§ Venue keys). That client hosts no master and no keyring.

---

## What exists today

| Piece | Where |
|---|---|
| Several accounts on one device, each with its own vault and passkey; switching is logout and login | frontend `pq-vaults-registry`, `Account_Selector` |
| Moving a whole identity: backup file, device link | frontend backup, `docs/device-link.md`; device-link code in the SDK |
| Encrypted per-account slots | User Storage (`pq_user_storage.done.md`) |
| Identities derived from an account, a per-signer outbox, the owner gate for derived cards | frontend notes (`sessionIdentities.ts`, `derivedCard.ts`) |
| Persona derivations with golden vectors | SDK `personas.ts` |

Constraints:
- **A passkey and a browser vault belong to one domain.** An app on one
  domain cannot read an account kept by an app on another; moving an account
  across domains is an explicit transfer (file, device link).
- **An identity is not tied to a server.** Separate identities per server are
  a choice the person makes, usually so the servers cannot link them.

---

## Principles

- **An account is the same whether it is a master or added.** Its contacts,
  dialogs, notes, room keys, settings and backups live in its own User
  Storage under its own keys, as they would if it stood alone. Being added
  means one thing: its keys are also in a keyring.
- **No server learns how a person's identities relate.** Keyring and persona
  list are opaque slots. While an identity is active the client signs and
  proves keys only as that identity, never as the master, and writes nothing
  that ties the two together. Accepted exceptions: the persona recovery scan
  (§ Personas) and the connection-level link the notes spec accepts.
- **An added account keeps working on its own.** Adding it does not remove
  its vault, passkey or backups elsewhere; its keys then exist in two places,
  which is the person's choice.
- **One passkey per device.** Switching the master re-locks the device's
  vault around the new master's keys under the same passkey.
- **Nothing is removed without the person.** Keyring entries and personas
  stay until the person detaches them (after an export is offered) or hides
  them; no operation, switching the master included, removes one.
- **Formats and their owners.** Persona derivations, the device-link code and
  the account payload are SDK contracts (`@buckitup/pq-client`). The keyring
  slot and its operations belong to BuckitUp's client.

---

## Personas

Derived like the notes identity, from the creating account's keys and an
index (`personas.ts` in the SDK, with golden vectors):

```
IKM  = sign_skey || crypt_skey                    # the creating account's
salt = "buckitup/persona/v1"
info = I2OSP(index, 4) || label                   # labels and lengths as for the notes identity
```

- The list is the creating account's `$keyed` slot `personas`:
  `{ "personas": { "<index>": { "name": "…", "created_at": 0 } } }`.
- **Creating needs the server:** the next index is the lowest one with
  neither a slot entry nor a card on the server; the card is published at
  once, with the person's chosen name, and never becomes the owner of a
  server without one (the owner gate derived cards already pass).
- **Recovery without the slot:** derive indexes 0, 1, 2… and look their cards
  up; stop after 5 indexes in a row without a card. The lookups tell the
  server the hashes belong together; accepted.
- A persona cannot be cut off from its account. Hiding removes it from the
  list; an identity that must leave the person is an added account instead.
- A persona cannot become a master: it has no backups of its own.

---

## Keyring

A `$keyed` User Storage slot `keyring` of an account, one entry per added
account:

```json
{ "entries": {
    "<user_hash>": {
      "label": "…",
      "server": "https://…",
      "card": { "...": "the account's public user_cards row" },
      "keys": { "sign_skey": "…", "crypt_skey": "…", "contact_skey": "…", "evm_skey": "…", "meta_seed": "…" },
      "added_at": 0
} } }
```

- **`keys`** is the full key set of the account payload, as a backup carries
  it. With all of it the account keeps its guardian role, manages its own
  community backup, and can be exported again whole.
- **`server`** is the account's own server: device link sends it; for a file
  the client asks, defaulting to the app's server.
- One top-level key per entry, so two devices adding at once merge. The slot
  is encrypted like every slot, under a key derived from its account's
  `crypt_skey`; restoring that account restores its keyring.
- **Checks** before an entry is written and when it is read: `user_hash`
  matches `sign_pkey`, the signing key signs for it, the KEM key decapsulates
  a test encapsulation to `crypt_pkey`. A failing entry is shown as damaged,
  with "Add again", and is never activated.
- Secret keys are read from the slot only to activate the account and wiped
  when it stops being active.

### Adding an account

One payload, `{ identity, keys }`, from three sources:
1. **a backup file;**
2. **device link:** the master's app shows a code; the other app — on
   another device, or on another domain on this device, where the code is
   copied from one tab and pasted into the other — sends the account and its
   server;
3. **another account on this device**, opened with its own passkey.

Adding the master or an account already in the set is refused.

### Device link across servers

Both apps meet in a relay room on a server. The code names the server of the
app that shows it, `<room>.<fingerprint>@<origin>` (SDK `deviceLink.ts`); the
other app joins that server; a code without a server means the app's own.
HTTPS only, localhost excepted. Trust does not change: the server only
relays, and the fingerprint and the six-digit comparison prove who is at the
other end. The backend socket accepts any origin (`check_origin: false` on
`/webrtc-socket`). Deployments with a Content-Security-Policy need
`connect-src` open for `wss:`.

---

## Activating an identity

Activating identity S gives the same app as signing in to S alone, minus the
passkey:
- the active context is torn down as logout does, except that the master's
  vault stays open; S is opened with its keys (derived for a persona, from
  the keyring for an added account); back to the master, from the vault;
- nothing ties S to the master on the server: while S is active nothing is
  signed or proven by the master, and the master's `personas` and `keyring`
  slots are written only while the master is active;
- S's pending writes stay in its own outbox and go out when S is active again;
- an identity that is not active receives nothing until the person switches
  to it — no unread counters, no notifications;
- logout locks the vault and wipes every key; a reload returns as the master.

---

## The person's set

The switcher lists the master's personas and keyring and, for every account
in the keyring, its own personas and keyring, recursively, each identity
once. A device therefore sees everything the person added on any device,
whichever account it opens as master; no state is kept in step between
devices. Reading another account's slots means reading its User Storage
with its keys, as that account.

---

## Servers

Servers sync with each other only within one organisation; a partner's
servers do not sync with BuckitUp's. A client talks to its build's server.

An added account whose `server` is another organisation's is activated like
any other: an identity is not tied to a server, and its card is published
here on first use, under this server's access rules. Its data on its own
server is not here. The client shows where it is: whenever the active
identity's `server` differs from the app's, the identity display and the
switcher say "from <its server> · on <this server>". Reading an identity's
own server from this app is phase 3.

---

## Switching the master

Per device; other devices keep their own master.
1. The new master is an added account of the set.
2. If the old master is not in the new master's keyring, it is added with its
   full keys.
3. The device's vault is re-locked around the new master's keys under the
   same passkey.

Nothing else moves: the old master's slots stay where they are and the set
is still reached through the keyrings.

---

## Recovery

- What a backup holds does not change. Restoring any account brings back its
  User Storage, with its personas list and keyring, and through them the
  rest of the set.
- Personas also come back without the slot (§ Personas, recovery).
- Backups of master and added accounts are independent. An account's existing
  backups stay when it becomes a master or is added. The passkey copy on the
  server restores the account it was made for, which leads to the rest.
- After switching the master the client may suggest a community backup for
  the new master, offering the old master's guardians; nothing depends on it.

---

## Delegation

Phase 4, for venues of a partner's client.
- Only the venue's owner delegates; the delegate receives the venue's full
  keys and can act as the venue.
- A delegate can pass the keys on: keys are bearer secrets, and the client
  does not pretend otherwise.
- Withdrawing a delegation means moving to a new venue identity. Revocable
  per-staff access is not part of this requirement.
- Before delegation ships, the dangerous operations on a venue (moderation
  mode, deletion) require the owner's signature, as
  [reviews/pq_origin.done.md](reviews/pq_origin.done.md) plans in its Phase 3
  note.

---

## Phases

| Phase | Scope |
|---|---|
| **1. Identities in one session** | Activation without a passkey; personas; keyring, added from a file or another account on this device. Notes (U3) land the per-identity session first |
| **2. Device link and the set** | Adding by device link, across servers; the person's set across keyrings; export, detach; switching the master |
| **3. Several servers** | An added account used on its own server from the master's app |
| **4. Delegation** | Owner-only dangerous operations on a venue first, then delegate |

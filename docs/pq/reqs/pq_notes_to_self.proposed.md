# PQ Notes to Self

A person keeps any number of named notes: chats with no one on the other
side. Notes are ordinary dialogs, synced to every device of the account like
any other messages. The server cannot tell that they are notes, how many a
given account has, or whose they are.

Status: proposed. Nothing here is implemented.

Notes are the first **derived subaccount** of [pq_subaccounts.proposed.md](pq_subaccounts.proposed.md):
an identity whose keys the account derives from its own instead of keeping
them in a keyring. Building notes builds the per-identity session that
subaccounts need in their phase 1.

---

## Why not a dialog with oneself

The simplest form, the account writing to itself (`sender_hash = peer_hash =`
the account), works with today's protocol, but every row names the account.
The server sees that it keeps notes, how many messages it writes there, and
when. The design below moves the notes to identities the server cannot tie
to the account.

---

## Identities

### Notes identity

One per account, derived from the account's secret keys, so that every device
of the account arrives at the same identity without syncing anything:

```
IKM  = sign_skey || crypt_skey                    # the account's
salt = "buckitup/notes-identity/v1"

sign seed    = HKDF-SHA3-256(IKM, salt, info = "sign",    L = 32)  → ML-DSA-87 keygen
crypt seed   = HKDF-SHA3-256(IKM, salt, info = "crypt",   L = 64)  → ML-KEM-1024 keygen
contact seed = HKDF-SHA3-256(IKM, salt, info = "contact", L = 48)  → secp256k1: (OS2IP(seed) mod (n − 1)) + 1
```

HKDF as in [09_symmetric_keys.md](../invariants/09_symmetric_keys.md). The
identity has a normal `user_cards` row ([pq_user.done.md](pq_user.done.md)).
Its `name` (required, non-empty) is a plausible name picked from a word list
by the identity's own key, so every device publishes the same card and the
name does not mark it as a notes identity.

### Note peers

`dialog_hash` is fixed by the two participants ([pq_dialogs.done.md](pq_dialogs.done.md)
§ `dialog_hash`), so one identity has only one dialog with itself. Each note
is therefore a dialog between the notes identity and a **note peer** of its
own, derived from the notes identity and the note's id:

```
IKM  = sign_skey || crypt_skey                    # the notes identity's
salt = "buckitup/notes-peer/v1"
info = note_id || label                           # label: "sign" | "crypt" | "contact", lengths as above
```

`note_id` is 16 random bytes (hex in storage). It is random, not a counter,
so that two devices creating notes offline never collide.

A note peer has a `user_cards` row (needed by the `dialog_keys` foreign key;
card ingest is never chain-gated, [pq_access_gating.done.md](pq_access_gating.done.md))
and never writes anything else. Its secret keys are used only to sign its
card; since they derive from the note's id, any device can republish the card
where it is missing, for example on another server.

---

## A note is a dialog

Everything follows [pq_dialogs.done.md](pq_dialogs.done.md) unchanged, with
the notes identity as the author and the note peer as the peer:

- `dialog_hash` from the two `user_hash` values;
- `sender_msg_key` from the notes identity's keys and the note peer's
  `user_hash` (salt `buckitup/dialog-mk/v1`); one key per note;
- a `dialog_keys` row from the notes identity, wrapped to the note peer's
  `crypt_pkey`;
- messages, versions, edits, reactions, files and retractions as in any
  dialog.

Reading needs only the notes identity: the author re-derives
`sender_msg_key` (pq_dialogs § Key wrapping). No receipts are ever written,
since the peer never reads; the UI shows a note's messages as saved, not
delivered.

`@buckitup/pq-client` implements these derivations
(`dialogs` module, frontend branch `feat/pq-client-package`). The frontend's own dialog code still mixes `evm_skey`
into `sender_msg_key`; notes use the spec's derivation from the start.

---

## The list of notes

Names and order live in the account's User Storage, in a named slot
([pq_user_storage.done.md](pq_user_storage.done.md); frontend `slots.ts`):

```json
{ "notes": {
    "<note_id>": { "name": "…", "created_at": 0 }
} }
```

- Keyed by note id and written with `patchSlotJson` and `$keyed`, so notes
  created, renamed or removed on two devices at once merge.
- The slot is the account's own, encrypted and at a random address; writing
  it looks like any settings change.
- **Rename** patches the name. **Delete** retracts the note's messages
  (signed tombstones), sets `deleted_flag` on its `dialog_keys` row and
  removes the entry.
- If the slot were lost, the notes are not: the notes identity's
  `dialog_keys` rows list the note peers, and their messages decrypt with
  the notes identity's keys alone. Only the names are lost.

---

## Writing as the notes identity

The client signs, proves keys and queues writes as the notes identity, not
as the account:
- ingest with the notes identity's PoP;
- the outbox records which identity signs each pending write;
- shape subscriptions by `sender_hash` = the notes identity.

This is the per-identity session of [pq_subaccounts.proposed.md](pq_subaccounts.proposed.md)
§ Session, limited to one extra identity that is always active.

### Access modes

| Mode | What the notes identity needs |
|---|---|
| `open` | Nothing |
| `guarded` | A vouch chain for writes. By default the account vouches for it, as for any person it invites |
| `trust` | The same chain, with read scopes as well, and read sessions as the notes identity |

The vouch is the one row tying the account to the notes identity, and it
says only "the account invited someone". The alternative, approval by the
server owner like any new user, leaves no row at all but needs the owner to
act; whether the client offers it is open.

---

## What the server can and cannot see

| Sees | Does not see |
|---|---|
| An identity (the notes identity) writing to several identities that never reply | That they are notes, or whose |
| Their sizes and times | The content, the names, which note a message continues |
| In `guarded`/`trust`, that the account invited the notes identity | What the notes identity does with the invitation |
| The connection both identities use: same device, same address, close times | — |

The last row is the residual link: a server that correlates connections and
timing can guess the two identities belong to one person. Hiding it needs a
separate connection per identity and is out of scope.

---

## Recovery, devices, subaccounts

- Every device of the account derives the notes identity and reads the
  slot: notes appear on all devices with no extra step.
- Restoring the account (backup file, community backup) restores the notes:
  its keys derive the identity, its User Storage holds the names.
- Every account has its own notes. A subaccount activated from a master
  brings its notes with it, derived from its own keys.

---

## Phases

| Phase | Scope |
|---|---|
| **1. Identity and session** | Derivations with golden vectors (library), notes identity card, per-identity signer, PoP and outbox |
| **2. Notes** | The slot, create / rename / delete, note peers, the chat view without a peer |
| **3. Access modes** | Vouch for the notes identity in `guarded` / `trust`; read sessions as it |

## Open questions

1. In `guarded` and `trust`, offer owner approval instead of the account's
   vouch, for people who want no link at all?

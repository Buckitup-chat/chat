# PQ Subaccounts

One person, several identities. A **master account** holds the secret keys
of the person's **subaccounts** and acts as any of them where it is needed.
This requirement sets the scope and the decisions taken so far; the open
questions at the end remain.

Status: proposed. Nothing here is implemented.

---

## Terms

| Term | Meaning |
|---|---|
| **Identity** | A `user_cards` row: ML-DSA-87, ML-KEM-1024 and secp256k1 keys, `user_hash` from `sign_pkey` ([pq_user.done.md](pq_user.done.md)). Not bound to a server: the same identity can be published on any. |
| **Master account** | The identity whose keys are locked by the person's passkey on a device. It holds the keyring. One per person at a time. |
| **Subaccount** | Any other identity whose secret keys the master holds: a venue (origin), an identity the person uses on another server, an identity delegated to them. |
| **Keyring** | The master's list of subaccounts with their secret keys, encrypted under the master's keys. |
| **Activate** | Act as a subaccount: sign its rows and key proofs, read its dialogs. |

---

## Use cases

### U1. Venues (origins) — owned subaccounts

A venue is already modelled as a subaccount: its own `user_cards` identity,
bound to its owner by `owner_cert` ([reviews/pq_origin.done.md](reviews/pq_origin.done.md)).
Its keys must reach every device of the owner ("Origin keys in User Storage",
[reviews/pq_reviews.in_progress.md](reviews/pq_reviews.in_progress.md) Phase 3),
and the owner acts as the venue to reply to guests and moderate reviews.
Partner integrations depend on it ([pq_partner_venue_messaging.proposed.md](pq_partner_venue_messaging.proposed.md),
branch `docs/partner-venue-messaging`).

### U2. Delegating a venue to staff

The review specs intend the venue identity to be "delegated to an employee
without exposing the owner's personal identity or granting irreversible
powers" ([reviews/pq_origin.done.md](reviews/pq_origin.done.md) § Origin,
[reviews/pq_reviews.in_progress.md](reviews/pq_reviews.in_progress.md)). No
mechanism exists: the sandboxes export the venue's identity as a file and
import it elsewhere.

A staff member needs the venue's secret keys, not only rights:
- reading a review before approving it decrypts `review_post_right` with the
  venue's ML-KEM key;
- replying to a guest unwraps the dialog key with it and signs as the venue.
Vouch scopes grant writes on the server; they cannot grant reading ciphertext.

### U3. Accumulating identities from many servers

A person uses a different identity on each server (each domain): one on a
BuckitUp server, one on a partner's, one on a venue's device. They want one
account that keeps all of them and activates the right one for each
conversation, instead of one passkey and one app per identity.

The first step is **absorbing** an account into another: its keys move from
its own vault into the master's keyring, and it becomes a subaccount. Which
account is the master is the person's choice and can change.

### U4. Notes to self — derived subaccounts

Notes are dialogs of a hidden identity derived from the account's own keys,
so that the server cannot tell they are notes or whose they are
([pq_notes_to_self.proposed.md](pq_notes_to_self.proposed.md)). A derived
subaccount needs no keyring entry: every device of the account derives it.
Notes are the first user of the per-identity session below.

---

## What exists today

| Piece | Where | Relevance |
|---|---|---|
| Several accounts on one device | frontend `pq-vaults-registry`, `Account_Selector` | Each account has its own vault and passkey; one is signed in at a time; switching is logout and login |
| Moving a whole identity | frontend backup file (password-protected), device link (QR, ML-KEM-1024, `docs/device-link.md`), `exportVaultKeys` / `importVaultKeys` | Carries every secret key of an identity; today it lands in a vault of its own, not in another account |
| Encrypted per-user storage | User Storage, named JSON slots (`pq_user_storage.done.md`; frontend `slots.ts`) | Readable on every device of its owner; the natural home for a keyring |
| Recovery | Backup & Recovery (frontend `docs/backup-recovery-plan.md`) | Restores the master's keys; anything kept in the master's User Storage comes back with them |
| A client for several servers | `@buckitup/pq-client` transport, server as a parameter (frontend `packages/pq-client`) | One app can sign and read on many servers |
| Client limits today | Session holds one identity: one `sign_skey`, read sessions keyed by shape, outbox signed as the current user | All of this becomes per identity |

Constraints that shape the design:
- **A passkey and a browser vault belong to one domain.** An app on one
  domain cannot read an account kept by an app on another. Moving an account
  across domains is an explicit transfer (file, QR), never shared storage.
- **An identity is not tied to a server.** Using one identity on several
  servers is possible today; separate identities per server are a choice the
  person makes, usually so the servers cannot link them.

---

## Model

### Principles

- **An account is the same whether it is a master or a subaccount.** Its
  contacts, dialogs, room keys, settings and backups live in its own User
  Storage under its own keys, as they would if it stood alone. Being a
  subaccount adds one thing: its identity keys are also kept in a master's
  keyring.
- **No server learns how a person's accounts relate.** The keyring is an
  opaque slot in the master's User Storage. Acting as a subaccount, the
  client signs and proves keys only as that subaccount, never as the master,
  and writes nothing that ties the two together. The one link that exists by
  design is a venue's `owner_cert`, which the review protocol publishes.
- **A subaccount keeps working on its own.** Absorbing an account does not
  disable its own vault and passkey on its own domain; the person may still
  sign in to it there. Its keys then exist in two places, which is the
  person's choice.
- **One passkey.** Changing which account is the master does not change the
  passkey: the device's vault is re-locked around the new master's keys.
- **The master lives in BuckitUp's own client.** The keyring, its format and
  its operations belong to that client, not to the public contract of
  `@buckitup/pq-client`. A partner's client built on the library keeps the
  keys of the venues its users own ([pq_partner_venue_messaging.proposed.md](pq_partner_venue_messaging.proposed.md)
  § Venue keys) but hosts no master: no absorbing, delegating or switching.

### Keyring

A named User Storage slot of the master, one entry per subaccount, holding
identity keys only:

```json
{ "<user_hash>": {
    "kind": "owned | absorbed | delegated",
    "label": "…",
    "servers": ["https://…"],
    "keys": { "sign_skey": "…", "crypt_skey": "…", "contact_skey": "…", "evm_skey": "…" },
    "card": { "...": "the subaccount's public user_cards row" },
    "delegated_by": "<user_hash>",
    "added_at": 0
} }
```

- **owned:** created by the master (a venue), bound by `owner_cert` where the
  protocol has one.
- **absorbed:** an existing account moved in (U3).
- **delegated:** a venue's keys handed over by its owner (U2); the entry
  records who delegated it.

One top-level key per subaccount, so two devices adding at once merge. The
slot is encrypted like every slot, under a key derived from the master's
`crypt_skey`; restoring the master restores the keyring.

### Operations

| Operation | What happens |
|---|---|
| **Create** an owned subaccount | New keys, its `user_cards` row on the chosen server, keyring entry |
| **Absorb** an account | Its keys arrive by device link (below); the master checks them against the account's `user_cards` row (signature and KEM round trip) and adds an entry |
| **Export** a subaccount | Its keys leave by device link or as a backup file, as an account's do today |
| **Activate** | The session signs, proves keys and reads as that subaccount on its servers |
| **Detach** | The entry is removed from the keyring, optionally after an export |
| **Switch master** | The vault on the device is re-locked around the new master's keys under the same passkey; the keyring moves to the new master's User Storage, with the old master as a subaccount in it |
| **Delegate** a venue | The owner hands the venue's full keys to a staff member's keyring as `delegated` |
| **Withdraw a delegation** | The delegate cannot be made to forget the keys: withdrawal means a new venue identity |

### Moving keys between accounts and domains

- **Device link** already moves a whole identity between two devices of one
  account: a QR code read by eye, an ML-KEM-1024 session, the backend's
  Phoenix channel as transport (frontend `docs/device-link.md`). Absorbing
  and exporting reuse it, from one account's app to another's.
- **On one device across domains**, two apps cannot share storage. The
  proof of concept `docs/proposal/device_webrtc.md` (on the review branches;
  page `/dev/device_webrtc`) puts tabs of different origins on one device
  into a shared Phoenix room by device fingerprint and IP. It becomes the
  meeting point for a device link between the two apps once it has passed a
  security audit. It only lets them find each other: who is at the other
  end is still proven by the device link's code and ML-KEM session, never by
  the room.
- A backup file remains the fallback where no live transfer is possible.

### Recovery

Master and subaccounts have independent backups.
- **When an account becomes the master**, the client reminds the person to
  set up its community backup. If guardians are already set up for another
  of the person's accounts, they are offered as the default set; the person
  edits or approves the set before any share is sent.
- **Existing backups stay.** A backup made for an account when it was a
  master, or on its own, is not withdrawn unless the person asks for it.
- Restoring a master restores its keyring, so its subaccounts come back with
  it; a subaccount with its own backup can also be restored on its own.

### Delegation

- Only the venue's owner delegates.
- A delegate receives the venue's full keys and can act as the venue.
- A delegate can pass the keys on. Keys are bearer secrets: nothing in the
  protocol can stop it, and the client does not pretend to.
- Withdrawing a delegation means moving to a new venue identity. The old
  identity, with its dialogs and reviews, stays with whoever holds its keys.
  Revocable staff access (per-staff keys) is not part of this requirement.
- Before delegation ships, the dangerous operations on a venue (moderation
  mode, deletion) require the owner's signature, as
  [reviews/pq_origin.done.md](reviews/pq_origin.done.md) plans in its Phase 3
  note. Until then a holder of the venue's keys can perform them through
  peer sync.

### Session

The client holds the master and every activated subaccount at once:
- a signer per identity: rows, key proofs, the outbox (each pending write
  names the identity that signs it);
- read sessions per (identity, shape) on each server;
- subscriptions per identity and server;
- logout clears them all.

The first UI is the simplest: subaccounts as separate contexts the person
switches between.

---

## Phases

| Phase | Scope |
|---|---|
| **1. Keyring and owned subaccounts** | The slot, create, activate, per-identity session. Covers venues (U1) and the partner integration. The per-identity session may land first with notes (U4) |
| **2. Absorb, export, switch master** | Device link between accounts; the cross-domain meeting point after its security audit; master switch with the recovery reminder |
| **3. Several servers** | A subaccount used on its own servers from the master's app |
| **4. Delegation** | Owner-only dangerous operations on a venue first, then delegate |


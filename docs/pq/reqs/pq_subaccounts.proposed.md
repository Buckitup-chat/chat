# PQ Subaccounts

One person, several identities. A **master account** holds the secret keys
of the person's **subaccounts** and acts as any of them where it is needed.
This requirement sets the scope; the open questions at the end decide the
design.

Status: proposed, scope for discussion. Nothing here is implemented.

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

## Proposed model

### Keyring

A named User Storage slot of the master, one entry per subaccount:

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

- **owned:** created by the master (a venue). Bound by `owner_cert` where the
  protocol has one.
- **absorbed:** an existing account moved in (U3). Its old vault on its old
  domain is kept or deleted by the person.
- **delegated:** keys someone else handed over (U2). The keyring records who
  delegated it.

One top-level key per subaccount, so two devices adding at once merge. The
slot is encrypted like every slot, under a key derived from the master's
`crypt_skey`; restoring the master restores the keyring.

### Operations

| Operation | What happens |
|---|---|
| **Create** an owned subaccount | New keys, its `user_cards` row on the chosen server, keyring entry |
| **Absorb** an account | Its keys arrive by backup file or QR transfer, the master checks them against the account's `user_cards` row (signature and KEM round trip), adds an entry |
| **Export** a subaccount | Its keys leave as a backup file or QR transfer, as an account's do today |
| **Activate** | The session signs, proves keys and reads as that subaccount on its servers |
| **Detach** | The entry is removed from the keyring; optionally exported first |
| **Switch master** | A subaccount becomes the master (its keys move into a vault under a passkey), the old master becomes a subaccount in the new keyring |
| **Delegate** | A subaccount's keys go to another person's keyring as `delegated` |
| **Withdraw a delegation** | See open questions: with shared keys this cannot be enforced |

### Session

The client holds the master and every activated subaccount at once:
- a signer per identity: rows, key proofs, the outbox (each pending write
  names the identity that signs it);
- read sessions per (identity, shape) on each server;
- subscriptions per identity and server;
- logout clears them all.

---

## Phases

| Phase | Scope |
|---|---|
| **1. Keyring and owned subaccounts** | The slot, create, activate, per-identity session. Covers venues (U1) and the partner integration |
| **2. Absorb, export, switch master** | Moving accounts in and out (U3, first step); master switch with its effect on recovery |
| **3. Several servers** | A subaccount used on its own servers from the master's app; what each server learns |
| **4. Delegation** | Delegate and withdraw (U2), after the design questions below are settled |

---

## Open questions

**Master and switching**
1. When the master changes, does the new master get a new passkey, or does the existing passkey's vault re-lock the new master?
2. Recovery is set up for the master (guardians hold shares of its keys). On a master switch, is recovery re-made for the new master automatically, or does the person do it?
3. Can a subaccount still be signed into on its own (its old vault and passkey), or does absorbing it remove that?

**Accumulation across servers**
4. Must servers be unable to link a person's identities? The keyring sits on the master's server; other servers see only the subaccount they serve. Is that enough, or must the master's server not learn there are subaccounts at all?
5. Where does the master live: only in BuckitUp's app, or in any app built on `@buckitup/pq-client` (a partner's too)?
6. Absorbing from another domain: is a backup file enough, or is a QR transfer between two apps needed (device link between domains)?
7. In the UI, are subaccounts separate contexts the person switches between, or one inbox that marks which identity each conversation uses?

**Delegation**
8. Is handing over the venue's full keys acceptable (a delegate keeps them forever; withdrawing means a new venue identity), or must staff access be revocable? Revocable access needs protocol work: per-staff keys and re-wrapping of what they may read.
9. Who may delegate: the owner only, or the venue identity too? May a delegate pass it on?
10. Must the owner-only rule for dangerous operations ([reviews/pq_origin.done.md](reviews/pq_origin.done.md), Status note) be enforced before delegation ships? Today a delegate can change the moderation mode or delete the venue through peer sync.

**Format**
11. Should the keyring also be where room keys go once rooms exist (`pq_rooms`, TBD), as the previous generation kept room keys next to the user's?

# PQ Recovery Shares

## Purpose

Community backup splits the **friends' half** of a 32-byte wrap key `S` among
people the owner already trusts, and this is how one of those shares reaches a
guardian: as a message, in the dialog they already have. The content type is
registered in
[07_content_polymorphism](../invariants/07_content_polymorphism.md#recovery_share).

The scheme it serves is described in the recovery client's own documents
(`chat-frontend/docs/backup-recovery-overview.md`): `S` splits in two with a
one-time pad — a node half and a friends' half — and only the friends' half is
Shamir-split among guardians. A guardian set below the threshold learns nothing,
and a guardian set *above* it still learns nothing without the node plane. An
on-chain contract is the objective record of who asked for a recovery and who
approved it.

Client behaviour is owned by that repo's plan (Phase 2); this document owns the
wire contract and the lifecycle.

---

## Problem

The friends' half needs a transport with three properties at once, and picking
any two leaves a hole.

1. **Post-quantum in transit.** A share is long-lived — it sits on a guardian's
   device for years — so an adversary who records it today and breaks ECDH later
   still gets it. A recording attack against the friends' plane is not exotic;
   it is the expected one.
2. **Addressed to a person, not a key.** The owner chooses guardians from their
   contacts. Anything that asks the owner to handle a key, a QR or a file moves
   the failure into the part of the system that is hardest to make reliable —
   the human one.
3. **Auditable by the holder.** A guardian has to be able to see what they hold
   and for whom, or the social plane is a promise nobody can inspect.

Dialogs satisfy all three: `pq_dialogs` wraps every message with
`sender_msg_key` and ML-KEM-1024, contacts are how the owner already names
people, and a message is a thing both sides can look at.

What today's friends' plane does instead is ECIES to a stealth address, with the
ciphertext delivered **on chain** in `ShareInput[]` — keyed by the same
secp256k1 the chain is keyed by, and public forever. That is the transport this
document replaces, and replacing it is only worth something if the on-chain
slot stops carrying the same bytes (see §Issuing).

Two limits belong here rather than in a later surprise:

- **Dialogs buy the post-quantum property, not forward secrecy.** Per
  [pq_dialogs §Accepted trade-off](pq_dialogs.done.md), `sender_msg_key` is
  derived deterministically from the *sender's* long-term keys and never
  rotates. The sender here is the owner, so a leak of the owner's `crypt_skey`
  at any future date decrypts every share they ever issued, to anyone who kept
  the replicated dialog rows — every guardian at once, not one device. That is
  the recording attack of property 1, arriving through the transport chosen to
  answer it, and a later `reshare` does not help: the old ciphertext is already
  recorded. What a reshare does answer is a *guardian* device compromise, and
  there it is a rule rather than hygiene.
- **The node plane keeps its own transport.** Node shares are deposited over
  HTTP and released against `canDecrypt`; they never travel this way.

---

## Scope

**In scope:** issuing shares to guardians, what a guardian's client does on
receipt, how shares are superseded and revoked, and what the owner can see.

**Out of scope:** *returning* a share during a recovery. Issue happens between
two accounts that both exist — the owner has their keys, the guardian is a
confirmed contact, the dialog is already there. Return happens after the owner
has lost their signing key, their `user_hash` and their contact list, so the
recovering client is a new identity no guardian has ever met and there is no
dialog to send anything back through; a fresh optical handshake with every
guardian is exactly the in-person ceremony remote recovery exists to avoid.

The return path needs its own requirement (`pq_recovery_return.proposed.md`,
unwritten). Its shape is already visible — the on-chain round names a
`candidate` and the contract answers `canDecrypt`, which is precisely a way to
authorise delivery to someone you have never met — and it must answer one thing
this document cannot duck: that path is secp256k1-keyed, so property 1 does not
survive it, and the requirement has to say what bounds the exposure.

---

## Issuing

The owner's client, at backup time:

1. Generates the wrap key `S`, seals the vault under it, and splits it into a
   node half and a friends' half
   (`chat-frontend/src/lib/pq/vaultEnvelope.ts`).
2. Shamir-splits the friends' half into `total` shares with threshold
   `threshold`, where `total` exceeds the number of guardians being used today.
   The surplus are **spares** and stay in the owner's account.
3. Registers the secret on-chain, for the guardians being used today. This fixes
   `secret_id` and `version`, and also the guardian stealth-address set and the
   contract's approval quorum — a different quantity from the message's
   `threshold`, since the contract counts guardian approvals and the message
   counts Shamir shares.
4. Sends one `recovery_share` message per guardian being used today, in the
   dialog that already exists with that contact.

A share is issued to a **confirmed** contact only — confirmed in the client's
sense, since the contact list is client-side state and not a data-layer entity
([pq_review_contacts](reviews/pq_review_contacts.done.md)), not a vouch-token
check. An unconfirmed contact is a person the owner has not finished
identifying, and a backup is the worst place to discover that.

**What the on-chain share slot carries.** `addSecret` will not accept an empty
guardian set, and it stores `shareEncrypted` verbatim. If that field keeps the
ECIES copy, the share is public and property 1 buys nothing.

Leaving the field empty is not the answer either: the struct's `shareHash` is
then `keccak256("")` for every chat-delivered guardian, so nothing distinguishes
them from an on-chain one and the integrity anchor is gone. `ephemeralPubKey`
must still be populated regardless — without it a guardian cannot derive the
stealth key that signs their approval.

What this requirement needs from the contract is a share slot that separates
**membership** from **delivery**: a guardian entry that records the stealth
address and the delivery channel without pretending to carry bytes. That is a v2
change, and it belongs with the rest of them
(`chat-frontend/docs/backup-recovery-plan.md`, Phase 6). Until it exists, this
transport and the on-chain one cannot both be correct at once, and the
requirement is blocked on that rather than on anything in this repo.

### Spares, and what they cannot buy

The circle of helpers grows — someone new becomes trusted, someone drops off —
and generating shares with a reserve is cheap, so `total` exceeds the number
issued today.

**A spare does not enrol a guardian.** Two mechanisms refuse it, and both are
worth stating because the opposite is the natural assumption:

- The contract's guardian set is written only by `addSecret` and `reshare`;
  individual add and remove are deliberately unsupported, so a holder whose
  address is not in `_guardians[id][version]` cannot initiate or approve a
  round.
- Nor can the address be pre-registered. A stealth address is derived from the
  *recipient's* published meta-address, so it cannot be computed for someone
  who has not been chosen yet — and an address the owner's own client derived
  for nobody is an address whose spending key is in the owner's vault, which
  would let a compromised owner cast that guardian's approval.

So a spare buys custody only: its holder can hold a share and hand it back, and
that is the whole of it. Adding a guardian costs a `reshare` — a new split, a
new version, and a message to everyone — which is the price the contract charges
for making membership objective, not an oversight to route around. Spares remain
worth generating because a share handed to an *existing* guardian, or held
against a future reshare, costs nothing extra: the surplus sits in the owner's
vault sealed under `S`, and an attacker holding the vault already has `S` by a
shorter route.

---

## Holding

The guardian's client, on receiving a `recovery_share`:

- Validates the envelope per
  [07 §Invariants](../invariants/07_content_polymorphism.md#invariants) — a
  longer array is accepted and its tail ignored, not rejected.
- Stores it even when `secret_ref` names a deployment this build cannot reach,
  and says so to the owner. Silently dropping it is the worse failure: the share
  is valid, and an owner whose roster shows a holder who holds nothing is counted
  above the threshold while being below it.
- Refuses a second share at the same `(secret_ref, version)` that disagrees with
  the one it holds, rather than keeping both. Shares from two different splits
  combine without error into a wrong `S`, so a re-issue must hand out the same
  split — see §Open questions for the case that forces one.
- Reads `secret_ref` on-chain to confirm the secret exists and to learn its
  current `version` and revocation state. The holding is displayed against the
  dialog peer's `user_cards.name`: the chain answers with the owner's address,
  and nothing maps an address to a chat identity.
- Drops what it holds when the rules in §Dying fire.
- Holds the share until it can tell which secret it belongs to. Nothing in the
  envelope binds `secret_ref` to the sender, and the chain answers with an
  address that maps to no chat identity, so a contact can name a stranger's
  secret and the client cannot tell. Until that link exists (§Open questions) a
  holding is a claim by the dialog peer, and the owner's roster — not the
  guardian's — is what decides whether it is real.
- Confirms receipt to the owner. The mechanism is open — see §Open questions —
  because the dialog's receipts say `delivered` and `read`, and neither of them
  says *stored*.

A guardian is told plainly what they are holding and for whom, can see it in one
place, and can refuse: **a share may be given back**. That return is advisory —
it removes nothing from the contract, and only a `reshare` removes a guardian —
so it has to be visible to the owner as a prompt to reshare rather than as a
change that already happened.

---

## Dying

A share stops being valid in two ways, both observable:

| Event | Mechanism | What the holder does |
|---|---|---|
| Reshare, including dropping a guardian | Contract `version` bumps | Drops its share once the new epoch is safe (below) |
| Revoke | `revokeSecret` — `canDecrypt` is false forever | Drops the share; no round can ever use it again |

The holder watches the contract, not only their inbox: a guardian dropped from
the circle never receives a newer share, so a client that waits for one keeps a
share the owner believes is dead.

But it must not drop on the bump alone. A retained guardian who deletes v1 the
moment `version` becomes 2, before the v2 message arrives, holds nothing — and if
the owner's client dies between the transaction and the messages, *every*
retained guardian holds nothing and the friends' half is gone. So: a holder drops
a superseded share once it has received its replacement at the new version, or
once the owner's roster confirms it is no longer in the circle. A dropped
guardian, who will never receive a replacement, is the case the roster covers.

"Drops the share" is what a cooperating client does, and it is not a guarantee
the transport can make. The bytes were delivered as a dialog message, so the
revision carrying them stays in `dialog_messages_versions` on every device of
that guardian, and a client that simply does not run the drop keeps the share.
What revocation guarantees is on-chain: `canDecrypt` is false forever, so the
share opens nothing even if it is kept. Re-splitting under a new `S` is what
actually makes old bytes worthless, and `revokeSecret` does not re-split.

There is no expiry: a share nobody revoked is still good, because the owner's
ability to lose their keys does not expire either.

---

## What the owner sees

- Who holds a share, at what version, and whether receipt was confirmed.
- How many confirmed holders exist against the threshold — the only number that
  answers "is my backup real yet". A backup whose guardians have quietly drifted
  below the threshold is worse than none, because the owner is counting on it.
- When a guardian gives a share back, or a holding goes stale after a reshare.

That roster lives in the owner's `user_storage`, so a second device sees the same
picture rather than recomputing a different one from whatever dialog history it
has — as an ordinary slot reachable through the root map, **not** at a constant
uuid. A slot address that is the same for every account publishes that the record
exists, how large it is and when it last changed, which for this record is "this
account has a community backup, with this many guardians" — the very link
§Open questions is worried about. The guardian's own view is a projection over
the `recovery_share` messages they received.

---

## Open questions

- **How a return is expressed on the wire.** Giving a share back has no content
  type and no table today, and the bytes cannot actually be destroyed in this
  layer: a deletion is a new tip, while the revision carrying the share stays in
  `dialog_messages_versions` on every device of that guardian.
- **What "confirmed" means.** `delivered` and `read` are what the dialog offers;
  "I stored it" is neither, and the owner's threshold count is only honest if it
  counts the third thing.
- **Whether a guardian can watch the backup row.** Telling the owner their vault
  row has gone missing is a real feature, and the envelope cannot carry the
  address it would need: the locator is derived from `S` precisely so the row is
  unfindable, and publishing it to every guardian would undo that for no
  recoverable benefit. If the alert is wanted, it needs a mechanism that does not
  hand out the address.
- **What binds a share to its owner.** A guardian cannot verify that the sender
  of a `recovery_share` is the secret's on-chain owner: the contract answers with
  an address, and no published record maps an address to a chat identity. Until
  something does, a guardian's holding is only as trustworthy as the dialog it
  arrived in.
- **What forces a re-issue.** If receipt confirmation stays unresolved, an owner
  whose confirmation never arrives will re-issue — and `version` only moves on a
  reshare, so the re-issue carries the same one. Either re-issue must be defined
  as handing out the *same* split, or confirmation has to be reliable enough that
  nobody re-issues blind.
- **A guardian who starts their own recovery** makes the share they hold
  questionable. The owner should be told, and `chat-frontend`'s plan schedules
  it (Phase 7). What is open here is detection: an on-chain round is public, but
  linking a guardian's chat identity to an on-chain address is precisely the
  link stealth addresses exist to break.

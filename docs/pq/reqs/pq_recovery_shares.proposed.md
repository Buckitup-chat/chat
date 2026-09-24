# PQ Recovery Shares

## Purpose

Community backup splits the **friends' half** of a 32-byte wrap key `S` among
people the owner already trusts, and this is how one of those shares reaches a
guardian: as a message, in the dialog they already have — and how it comes back
when the owner needs it. The content types are registered in
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
  derived deterministically from the sender's long-term keys, never rotates, and
  is wrapped to the recipient's `crypt_pkey` in `dialog_keys`. So a direction
  opens to a later leak of *either* end: the sender's long-term keys re-derive
  it, the recipient's `crypt_skey` unwraps it. At issue that is the owner and
  each guardian; at return (§Returning) it is each guardian and the temporary
  account — whose `crypt_skey` alone opens every returned share, which is why
  that account is destroyed when the recovery ends. None of this is repaired by a
  later `reshare`; the old ciphertext is already recorded. What a reshare does
  answer is a guardian *device* compromise, and there it is a rule rather than
  hygiene.
- **The node plane keeps its own transport.** Node shares are deposited over
  HTTP and released against `canDecrypt`; they never travel this way. What
  bounds their secp256k1 exposure is the one-time pad: the node half alone says
  nothing about `S`, and the friends' half it would have to be combined with
  never leaves ML-KEM.

---

## Scope

Issuing shares to guardians, what a guardian's client does on receipt, how
shares are superseded and revoked, what the owner can see, and how a share
travels back during a recovery (§Returning). Both directions use the dialog by
default — §Returning names the one exception — so the friends' half is
post-quantum both ways; the node half is not (§Problem).

---

## Issuing

The owner's client, at backup time:

1. Generates the wrap key `S`, seals the vault under it, and splits it into a
   node half and a friends' half
   (`chat-frontend/src/lib/pq/vaultEnvelope.ts`).
2. Shamir-splits the friends' half into `total` shares with threshold
   `threshold`, where `total` exceeds the number of guardians being used today.
   The surplus are **spares** and stay in the owner's account. The whole split
   and its `split_id` are persisted in the vault **before** the next step: a
   client that registers and then loses the split can only comply with
   §Re-issuing by an immediate `reshare`.
3. Registers the secret on-chain, for the guardians being used today. This fixes
   `secret_id` and `version`, and also the guardian stealth-address set and the
   contract's approval quorum — a different quantity from the message's
   `threshold`, since the contract counts guardian approvals and the message
   counts Shamir shares. **The quorum must not be below the threshold**, and the
   reason is liveness: once quorum is reached, further approvals revert
   (`QuorumAlreadyReached`), and a guardian who did not approve does not release
   (§Returning). With quorum two and threshold three, only two shares can ever be
   released and an honest recovery cannot complete.
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
address and the delivery channel without pretending to carry bytes, plus a
per-version commitment to the split (§Re-issuing). That is a v2 change, and it
belongs with the rest of them (`chat-frontend/docs/backup-recovery-plan.md`,
Phase 6). Until it exists, this transport and the on-chain one cannot both be
correct at once, and the requirement is blocked on that rather than on anything
in this repo.

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
- Copies the share into the guardian's own `user_storage`, as an ordinary slot
  reachable through the root map (scheme:
  `chat-frontend/docs/task-user-storage-slot-ids.md`). The message is not a
  place to keep it: whoever holds the owner's keys can revoke its readability by
  blocking the guardian — `deleted_flag` on the owner's `dialog_keys` row, or a
  garbage KEM ciphertext in it ([pq_dialogs §1](pq_dialogs.done.md)) — and during
  a recovery the owner's keys are exactly what may be in the wrong hands. The copy is also what makes a
  guardian's holdings one lookup, which §Returning needs.
- May hold several shares of one split — a spare handed to an existing guardian
  is a second index, not a conflict. What it refuses is the same
  `(secret_ref, version, split_id, share_index)` with different bytes, and it
  treats a *different* `split_id` at the same `version` as a fault to report
  rather than a share to keep (§Re-issuing).
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
place, and can refuse: **a share may be given back**. Giving back is advisory —
it removes nothing from the contract, and only a `reshare` removes a guardian —
so it has to be visible to the owner as a prompt to reshare rather than as a
change that already happened.

---

## Returning

The journey through the owner's eyes is `backup-recovery-overview.md` §4. What
this document owns is the guardian's side of it.

1. The owner, locked out, reaches a guardian outside the app — a call, a
   meeting — and the guardian satisfies themselves that it is really them. This
   is the step phishing attacks, and no protocol replaces it; everything below
   only makes sure the guardian's judgement is the one that counts.
2. The owner starts a **temporary account** on a new device and gets its
   `user_hash` to the guardian — by any channel; step 3 checks it. The guardian
   opens the dialog — a dialog can be opened with any `user_hash`
   ([pq_dialogs §Flows](pq_dialogs.done.md)) — and it is the guardian who opens
   it, because the temporary account knows nothing: not `secret_ref`, which is
   keyed by the owner's EVM address in the lost vault, and not any guardian's
   `user_hash`, which was in the lost contact list. The guardian's first message
   carries `secret_ref`.
3. The temporary account answers with a
   [`"recovery_binding"`](../invariants/07_content_polymorphism.md#recovery_binding):
   `secret_ref`, its candidate address, and a signature by that address's key
   over `(secret_ref, its own user_hash)`, all inside the ML-DSA-signed dialog
   row. This is the only link between an on-chain `candidate` and a chat identity
   a guardian can verify: the EVM key is independent of the account's other keys
   and published nowhere, so it cannot be derived, and recording it on-chain would
   publish it. The signature proves that the candidate's key signed *some*
   `user_hash`; what proves that `user_hash` is the person's on the call is the
   **word code** both screens now show — ten words the owner reads out and the
   guardian compares with their own, which the guardian's app computes from the
   `secret_ref` it sent, the binding's candidate and the dialog peer. A
   `user_hash` swapped on its way to the guardian at step 2, or a candidate
   swapped on the way back, changes the words. The code is the first 110 bits
   of `SHA3-256("buckitup/recovery-code/v1\n" || secret_ref || "\n" || candidate || "\n" || user_hash)`
   over the UTF-8 strings, big-endian, read as ten 11-bit indices into the
   BIP-39 English list; 110 bits cannot be ground into a collision by minting
   candidate keys, and the code is spoken, which is why it is words.
4. A guardian **initiates** the round and each guardian **approves**, naming as
   `candidate` the address from the binding it verified — the contract has no
   round-level candidate; the first address to reach quorum becomes the
   recipient. Each guardian picks the holding from their own list, which is why a
   holding has to be findable in the guardian's account (§Holding).
5. After the timelock, each guardian's client sends its share back as a
   `recovery_share_return` in the dialog with the temporary account, subject to
   the gate below. The nodes release the node half to the same recipient.
6. The temporary client rebuilds the friends' half, combines it with the node
   half into `S`, finds and opens the vault, and the owner is back in their
   **original** account: its keys are in the vault. The temporary account was
   only ever the return address.
7. The owner, from the original account, **reshares** — a new `S`, a new split,
   a new version — and the temporary account is **destroyed**, keys and vault. Its
   `crypt_skey` unwraps every returned share, its EVM key keeps `canDecrypt` true
   until the round is cancelled, and the node half was released to it. A
   recovery that ends without this step has moved the secret onto a device
   nobody was told to wipe (overview §4, steps 5–6).

**The send gate is this guardian's own vote, not the round's outcome.** The
client releases a share only when, on chain: `recoveryActive` holds; a recipient
is elected (`recoveryRecipient != 0`); that recipient is the candidate from the
binding *this guardian verified* and the one it approved (`hasApproved` — which
is also true of two zero addresses, so the elected check is not optional); the
recipient is not the owner; `executeAfter` has passed; and the held share's
`version` equals the contract's current one, since a guardian still waiting for
its replacement after a reshare (§Dying) is in the new set but holds the old
split. Gating on `canDecrypt` alone would let the quorum's judgement release a
share its holder never voted for — and `canDecrypt` is true for the owner with
no round at all, which would skip the timelock and the veto. A guardian who did
not vote before quorum cannot vote after it and does not send; with quorum ≥
threshold, the voters' shares suffice.

Sending on approval, before the timelock, would hand the share over while the
owner's veto still protects the node half and nothing else.

### Manual return

The dialog is the default route back, not the only one. When the guardian
cannot open the dialog, or the temporary account cannot read it, while the
server itself is up, a guardian and an owner already talking on a call or in
another messenger finish there, with text. This is not offline recovery: the
round still runs on chain, and the temporary account still needs the server for
its card and, later, for the vault. It is the one exception to the "no file
hand-off" rule of `chat-frontend/docs/backup-recovery-overview.md` §6 (owner
decision, 2026-09-24), and it gives up §Problem's property 2 for this leg: two
people carry a binding, a block and two codes by hand.

The same three things cross as in the dialog, as text, and the dialog's checks
are rebuilt where it gave them for free:

1. **Guardian → owner: `secret_ref`**, in the clear, in the first contact.
2. **Owner → guardian: the binding** of §Returning step 3, in the clear, with
   the word code read out. The guardian's app computes the words from the
   `secret_ref` it sent and the candidate and `user_hash` in the text it was
   handed; the `user_hash` the words confirm stands in for the dialog peer
   ([07 § recovery_binding](../invariants/07_content_polymorphism.md#recovery_binding)).
   With the binding verified, the app fetches the temporary account's card by
   that `user_hash`, checks `crypt_cert` ([pq_user](pq_user.done.md)) and
   keeps `crypt_pkey`.
3. **Guardian → owner: the sealed block**, in a second contact, once the send
   gate passes — after the timelock, so days after the first. The app
   encapsulates ML-KEM-1024 to `crypt_pkey`, derives
   `key = HKDF-SHA3-256(ss, "buckitup/recovery-return/v1", "seal|" || secret_ref, 32)`
   ([09](../invariants/09_symmetric_keys.md)) and a six-digit code from
   `"sas|" || secret_ref` exactly as device-link does (`chat-frontend`,
   `src/lib/pq/deviceLink.ts`: L = 4, big-endian, mod 10⁶), and emits

   `BUCKITUP-SHARE.<base64(kem_ct)>.<sealed>.<guardian user_hash>.<base64(sig)>`

   where `sealed` is `vaultEnvelope.sealWithKey(key, json)` verbatim — the
   vault row's `version || nonce || AES-256-GCM`, base64 — over the same
   `recovery_share_return` envelope the dialog would carry, and `sig` is the
   guardian's ML-DSA signature over the UTF-8 of the block up to the third
   segment. The receiver strips whitespace before parsing, since messengers
   wrap a 2.5 KB line. The guardian reads out the six digits; the owner's app
   derives its own after decapsulating and **imports nothing until the person
   confirms they match** — a block a relay substituted was encapsulated by
   someone else. The signature does not replace that check: the recovering app
   has no authenticated list of guardian `user_hash`es to test a signer against.
   It is for afterwards, when the owner has one and the block is the record of
   who released what.

What the other channel sees: `secret_ref`, the binding and the block. The
share is ciphertext, so property 1 holds on this route as on the dialog. The
binding is not, and it ties two messenger accounts to `secret_ref` and a
candidate — the link stealth addresses exist to break, and the reason to prefer
the dialog where it is available.

---

## Re-issuing

A re-issue resends the same bytes; that is harmless. A **new split** under the
same `version` is not: `version` moves only on a `reshare`, and two splits under
one number combine without error into a wrong `S`. So a new split happens only
through `reshare`, and every share names its split: `split_id` is opaque, equal
across one split's shares and different between splits, compared for equality
only. Random per split is enough for that.

What `split_id` does not do is authenticate a share. A malicious guardian copies
the id from their own envelope and returns junk; the recovering client cannot
tell which share was bad, only that the vault did not open. Checking a share
needs a commitment to the split, bound on-chain per `(id, version)` in the v2
slot (§Issuing), and each share has to travel with what checks it against that
commitment — reserved as `split_proof`, appended to both envelopes. Before any
VSS a Merkle root over all `total` shares is the commitment and a share's proof
path is what travels; a root alone verifies nothing. If VSS comes, the commitment has
to be **hiding** — Feldman's `C_0 = g^{secret}` yields the friends' half to a
discrete-log adversary, which is the property this whole transport exists to
deny, and the reason `backitup-smart-contracts` SI-1 chose Feldman (shares were
ECIES-sealed) no longer holds here.

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

There is no expiry. A share nobody revoked is still good, because the owner's
ability to lose their keys does not expire either; a client must not age a
holding out.

"Drops the share" is what a cooperating client does — the message revision and
the `user_storage` copy both — and it is not a guarantee the transport can make.
The revision carrying the bytes stays in `dialog_messages_versions` on every
device of that guardian, the copy's old value stays in `user_storage_versions`
after its tombstone, and a client that simply does not run the drop keeps the
share. What revocation guarantees is on-chain: `canDecrypt` is false forever, so
the share opens nothing even if it is kept. Re-splitting under a new `S` is what
actually makes old bytes worthless, and `revokeSecret` does not re-split.

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
§Open questions is worried about. The guardian's own view is read from the
copies in their `user_storage` (§Holding).

---

## Open questions

- **How giving a share back is expressed on the wire.** Refusing custody has no
  content type and no table today, and the bytes cannot actually be destroyed in
  this layer (§Dying).
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
  an address, and no published record maps an address to a chat identity. The
  same signed binding §Returning uses for the candidate would work here — the
  owner's EVM key signing over `(secret_ref, owner's user_hash)` — and would
  settle *did its owner send it*; *is this a real share of that secret* is the
  commitment question in §Re-issuing.
- **A guardian who starts their own recovery** makes the share they hold
  questionable. The owner should be told, and `chat-frontend`'s plan schedules
  it (Phase 7). What is open here is detection: an on-chain round is public, but
  linking a guardian's chat identity to an on-chain address is precisely the
  link stealth addresses exist to break.

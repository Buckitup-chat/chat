# Identity Revocation — closing a compromised account

## Purpose

An identity is its key ([`user_hash`](pq_user.done.md) derives from
`sign_pkey`), and the key cannot be rotated. Once the key may be in someone
else's hands, the only safe move is to end the identity and let everyone who
trusts it know. This requirement defines that move: a signed, permanent
**identity revocation**.
- every server refuses the identity's writes from then on;
- every client shows its contacts that the account is closed;
- the trust graph and the community backup stop relying on it.

Revoking the identity is safe in any hands. Whoever holds the key can only end
the identity with it, never hand it over. A thief who revokes destroys what
they stole. An owner who revokes loses nothing a thief had not already taken.
A device the identity owned is the one thing a revocation must not open up;
see [Device owner](#server-enforcement).

Status: proposed. This covers closing an account from a device that still
holds its key. Notifying without the key, through guardians, is
[Later](#later).

---

## Statement

A new table, `identity_revocations`, holds one row per revoked identity:

| Column | Type | Meaning |
|---|---|---|
| `user_hash` | `user_hash_type`, PK, FK `user_cards` | the identity that ends |
| `owner_timestamp` | `bigint` | signer's clock, unix seconds; informational only (see [Semantics](#semantics)) |
| `sign_b64` | `bytea` | ML-DSA-87 signature by the identity's own `sign_pkey` |

No reason, free text or successor field. A revocation may be signed by a
thief, so nothing in it is shown to people as the owner's words. Clients
render one fixed text for every revocation.

### Integrity

The row carries the integrity pair `owner_timestamp` and `sign_b64`
([Integrity](../invariants/02_integrity.md)), and no `deleted_flag`: it is
append-only and never tombstoned. When implemented, `02_integrity.md` lists it
under *Exceptions to `deleted_flag`*. Its `owner_timestamp` orders nothing
(see [Semantics](#semantics)). Replaying a statement only repeats it, so ingest
needs no proof of possession either.

### Signed payload

The `Signable` implementation adds a constant field that is not stored:

```
signable_fields = %{
  domain:    "buckitup/identity-revocation/v1",
  owner_timestamp: <owner_timestamp>,
  user_hash: <user_hash>
}
```

`Integrity.signature_payload/1` frames and sorts the fields as for every row.
The `domain` value separates the statement from rows of other tables and
versions it: a format change bumps it. The client builds the same bytes with
`canonicalPayload`. Both stacks pin them with one golden vector.

---

## Semantics

- **Absorbing.** An identity with any valid row is revoked, permanently.
  Nothing un-revokes it: not a newer card, not a second statement, not a
  deleted row. The table is insert-only, enforced by a trigger that raises on
  `UPDATE` and `DELETE` (the backend connects as a superuser, so a privilege
  `REVOKE` would not hold), and a conflict on `user_hash` keeps the stored
  row (`on_conflict: :nothing`). Every valid statement for an identity means
  the same thing, so which one a server keeps does not matter.
- **Independent of the card.** Revocation does not touch `user_cards`. A card
  update with any `owner_timestamp`, `deleted_flag` either way, or a new
  `name` changes nothing about it.
- **Independent of timestamps.** `owner_timestamp` is chosen by the signer and
  compared with nothing: a key holder who signed rows with far-future
  timestamps cannot outrun a revocation, and a backdated one decides nothing
  about which of the identity's rows are genuine. Each observer goes by the
  moment it learned of the revocation (see [Clients](#clients)).

---

## Ingest and sync

- **HTTP ingest.**
  - `/ingest` and `/ingest_each` accept `insert` for `identity_revocations`.
    The writer verifies the signature against the stored card's `sign_pkey`.
  - There is **no** proof-of-possession check: the statement carries its own
    signature, and replaying it is harmless.
  - `update` and `delete` are refused (insert-only, see [Semantics](#semantics)).
  - The card must already be stored: `422` otherwise.
- **Peer sync.**
  - `sync_persist(:insert, …)` validates the signature and inserts, keeping a
    stored row; `:update` and `:delete` are ignored.
  - `sync_required_parents` is the user card, as for vouch tokens.
- **Reads.** `identity_revocations` joins the read-exempt shapes beside
  `user_card` and `vouch_token`. Clients read the whole table. Revocations are
  rare, and a whole-table read tells the server nothing about whose
  revocation a client cares about.

---

## Server enforcement

- **Writes.**
  - Every HTTP ingest refuses a revoked acting identity, **in every gate mode,
    `open` included**: `403 {"error": "identity_revoked"}` on `/ingest` and,
    per row, on `/ingest_each`. The one exception is an `identity_revocations`
    insert itself, which is accepted again so that a replay is idempotent.
  - One unconditional helper does it, with no gate-mode branch: an indexed
    lookup by `user_hash`, called at the top of `WriteGate.check_access/2`
    before the mode is read (so all shapes behind `and_gate` inherit it), and
    in every writer check that bypasses `WriteGate`: `user_card_allowed`,
    `vouch_token_allowed` and the review right candidates'
    `right_candidate_check`. It belongs nowhere inside `enforce/2`, which never
    runs in `open` mode.
  - Clients treat `identity_revoked` as permanent and drop the identity's
    queued writes instead of retrying them.
  - Peer sync does **not** refuse a revoked identity's rows. A server that
    refused rows another server accepted would never converge with it. Clients
    classify those rows instead.
- **Key proofs.** `KeyProof.prove/3` treats a revoked identity as
  `:unknown_user`, so it opens no read session and claims no device.
- **Reads.**
  - `open`: anyone reads without a session, a revoked identity included.
  - `guarded`: reads need a read session — a key proof with no chain check —
    so that a revoked identity, whose proofs fail, reads nothing. Today
    `guarded` reads are anonymous; with this, `ReadGate.enforced?/0` holds in
    `guarded` as in `trust`, and only `trust` checks the chain.
  - `trust`: unchanged; a session needs a key proof and a chain.
- **Trust graph.** The chain-distance query skips every vouch whose issuer is
  revoked, at every hop, and refuses a revoked subject: a revoked identity
  neither grants nor holds a place in any chain. A revocation carries no scope,
  so every insert, local or synced, flushes the whole resolved-chain cache.
- **Device owner.** A revoked owner must not leave the device more open than
  before, or a thief holding the owner's key would open it by revoking.
  - The gates treat a revoked owner as present but unable to vouch: in
    `guarded` and `trust` nobody's chain reaches it, so only the gate modes'
    own exemptions pass. `open` stays open.
  - The revoked key cannot act as owner, because its key proofs fail.
  - Nobody can take the device over remotely: neither ingest nor the owner
    claim registers a new owner while a revoked one is stored. A device gets a
    new owner only by reinstalling its firmware, which wipes AdminDB. The
    first person to sign in on it afterwards becomes the owner, as on a fresh
    device ([Bootstrap and Owner](pq_access_gating.done.md#bootstrap-and-owner)).
    That step needs physical access, which a thief who revoked the owner
    remotely does not have.

---

## Clients

- **Closing an account** is a deliberate, irreversible action, in Settings
  and at the end of a recovery. The client:
  1. shows what closing costs — every contact has to be met again, and the
     history stays readable but nothing more can be sent;
  2. signs the statement and ingests it;
  3. offers to revoke the account's community backup on chain, off by default:
     kept, it lets the owner recover the old account's data later; revoked,
     guardians and nodes drop their shares (`pq_recovery_shares` § Dying);
  4. signs out. Deleting the local data is offered, not done by default.
- **The revocation set.**
  - Every client syncs `identity_revocations` and keeps a persisted local set
    that only grows.
  - A revoked identity stays revoked locally, even if a server later serves a
    view without it.
  - The client records, per identity, when it first learned of the revocation.
- **A contact's revocation:**
  - The dialog shows one fixed banner — "This account was closed by its owner"
    — and the composer is disabled.
  - The contact's name comes from the local contact record, never again from
    the card.
  - Messages, edits and deletions from the identity that this client first
    sees after it learned of the revocation are shown labelled, not applied
    silently. Earlier history stays as it was.
  - The banner says what to do: do not trust new messages, change anything
    secret shared with that account, meet in person to reconnect.
- **Community backup:**
  - an owner whose guardian or node operator is revoked sees that holding as
    lost in the roster, with a reshare prompt;
  - a guardian sees "owner closed their account" on the holding and keeps it,
    since the owner may still recover the old account's data; it drops the
    holding when the backup is revoked on chain.
- **No successor.** A new account is a new identity. Contacts connect to it in
  person, as with any account.

---

## What revocation does not do

- It does not delete history, messages or files.
- It does not point anywhere: no "my new account is".
- It is not reversible, by anyone.

---

## Later

- **Notice without the key.** A revocation statement pre-signed when the
  account is created, held by the account's guardians in shares, and
  published by them when the owner has lost every device. This needs a
  pending state and an objection by the old key, because guardians could
  otherwise kill an account the owner still uses.
- **Public anchor.** An optional commitment on chain, to give a revocation a
  time no server controls.
- **Reports by others.** Signals about someone else's account, weighted by
  each viewer's own trust graph and never enforced network-wide.

---

## Open questions

1. Should `identity_revocations` rows carry the card's `sign_pkey`, so a
   revocation verifies even where the card has not arrived yet?

---

## References

- [Access Gating](pq_access_gating.done.md): write gate, read sessions, owner
  bootstrap and claim.
- [Vouch Tokens](pq_vouch_tokens.in_progress.md): the chain-distance query.
- [User](pq_user.done.md): user cards.
- [Recovery shares](pq_recovery_shares.proposed.md): § Dying.
- [Integrity](../invariants/02_integrity.md): signed rows.

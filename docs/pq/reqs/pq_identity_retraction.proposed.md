# Identity Retraction — closing a compromised account

## Purpose

An identity is its key ([`user_hash`](pq_user.done.md) derives from
`sign_pkey`), and the key cannot be rotated. Once the key may be in someone
else's hands, the only safe move is to end the identity and let everyone who
trusts it know. This requirement defines that move: a signed, permanent
**identity retraction**.
- every server refuses the identity's writes from then on;
- every client shows its contacts that the account is closed;
- the trust graph and the community backup stop relying on it.

Retracting the identity is safe in any hands. Whoever holds the key can only end
the identity with it, never hand it over. A thief who retracts destroys what
they stole. An owner who retracts loses nothing a thief had not already taken.
A device the identity owned is the one thing a retraction must not open up;
see [Device owner](#server-enforcement).

Status: proposed. This covers closing an account from a device that still
holds its key. Notifying without the key, through guardians, is
[Later](#later).

**Terms.** *Retraction* ends an identity. It is distinct from *revoking* a
vouch ([Vouch Tokens](pq_vouch_tokens.in_progress.md), a tombstone on one
grant), from *retiring* a community backup on chain (the contract's
`revokeSecret`), and from *reviews*, a separate feature.

---

## Statement

A new table, `identity_retractions`, holds one row per retracted identity:

| Column | Type | Meaning |
|---|---|---|
| `user_hash` | `user_hash_type`, PK | the identity that ends |
| `sign_pkey` | `bytea` | the identity's ML-DSA-87 public key |
| `owner_timestamp` | `bigint` | signer's clock, unix seconds; informational only (see [Semantics](#semantics)) |
| `sign_b64` | `bytea` | ML-DSA-87 signature by the identity's own `sign_pkey` |

The row verifies on its own: `user_hash` must be the hash of `sign_pkey`, as on
a [card](pq_user.done.md), and `sign_b64` must verify under that key. A retraction therefore
checks out anywhere with no lookup: on a server that never had the card,
offline, or outside the database (on paper, in a guardian's share, on chain).

No reason, free text or successor field. A retraction may be signed by a
thief, so nothing in it is shown to people as the owner's words. Clients
render one fixed text for every retraction.

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
  domain:          "buckitup/identity-retraction/v1",
  owner_timestamp: <owner_timestamp>,
  sign_pkey:       <sign_pkey>,
  user_hash:       <user_hash>
}
```

`Integrity.signature_payload/1` frames and sorts the fields as for every row.
The `domain` value separates the statement from rows of other tables and
versions it: a format change bumps it. The client builds the same bytes with
`canonicalPayload`. Both stacks pin them with one golden vector.

---

## Semantics

- **Absorbing.** An identity with any valid row is retracted, permanently.
  Nothing un-retracts it: not a newer card, not a second statement, not a
  deleted row. The table is insert-only, enforced by a trigger that raises on
  `UPDATE` and `DELETE` (the backend connects as a superuser, so a privilege
  `REVOKE` would not hold), and a conflict on `user_hash` keeps the stored
  row (`on_conflict: :nothing`). Every valid statement for an identity means
  the same thing, so which one a server keeps does not matter.
- **Independent of the card.** Retraction does not touch `user_cards`. A card
  update with any `owner_timestamp`, `deleted_flag` either way, or a new
  `name` changes nothing about it.
- **Independent of timestamps.** `owner_timestamp` is chosen by the signer and
  compared with nothing: a key holder who signed rows with far-future
  timestamps cannot outrun a retraction, and a backdated one decides nothing
  about which of the identity's rows are genuine. Each observer goes by the
  moment it learned of the retraction (see [Clients](#clients)).

---

## Ingest and sync

- **HTTP ingest.**
  - `/ingest` and `/ingest_each` accept `insert` for `identity_retractions`.
    The writer verifies the row as in [Statement](#statement); no card is
    needed.
  - There is **no** proof-of-possession check: the statement carries its own
    signature, and replaying it is harmless.
  - `update` and `delete` are refused (insert-only, see [Semantics](#semantics)).
- **Peer sync.**
  - `sync_persist(:insert, …)` validates the signature and inserts, keeping a
    stored row; `:update` and `:delete` are ignored.
  - The row has no required parents.
- **Reads.** `identity_retractions` joins the read-exempt shapes beside
  `user_card` and `vouch_token`. Clients read the whole table. Retractions are
  rare, and a whole-table read tells the server nothing about whose
  retraction a client cares about.

---

## Server enforcement

- **Writes.**
  - Every HTTP ingest refuses a retracted acting identity, **in every gate mode,
    `open` included**: `403 {"error": "identity_retracted"}` on `/ingest` and,
    per row, on `/ingest_each`. The one exception is an `identity_retractions`
    insert itself, which is accepted again so that a replay is idempotent.
  - One unconditional helper does it, with no gate-mode branch: an indexed
    lookup by `user_hash`, called at the top of `WriteGate.check_access/2`
    before the mode is read (so all shapes behind `and_gate` inherit it), and
    in every writer check that bypasses `WriteGate`: `user_card_allowed`,
    `vouch_token_allowed` and the review right candidates'
    `right_candidate_check`. It belongs nowhere inside `enforce/2`, which never
    runs in `open` mode.
  - Clients treat `identity_retracted` as permanent and drop the identity's
    queued writes instead of retrying them.
  - Peer sync does **not** refuse a retracted identity's rows. A server that
    refused rows another server accepted would never converge with it. Clients
    classify those rows instead.
- **Key proofs.** `KeyProof.prove/3` treats a retracted identity as
  `:unknown_user`, so it opens no read session and claims no device.
- **Read sessions.**
  - `open`: anyone reads without a session, a retracted identity included.
  - `guarded`: reads need a read session — a key proof with no chain check —
    so that a retracted identity, whose proofs fail, reads nothing. Today
    `guarded` reads are anonymous; with this, `ReadGate.enforced?/0` holds in
    `guarded` as in `trust`, and only `trust` checks the chain.
  - `trust`: unchanged; a session needs a key proof and a chain.
- **Trust graph.** The chain-distance query skips every vouch whose issuer is
  retracted, at every hop, and refuses a retracted subject: a retracted identity
  neither grants nor holds a place in any chain. A retraction carries no scope,
  so every insert, local or synced, flushes the whole resolved-chain cache.
- **Device owner.** A retracted owner must not leave the device more open than
  before, or a thief holding the owner's key would open it by retracting.
  - The gates treat a retracted owner as present but unable to vouch: in
    `guarded` and `trust` nobody's chain reaches it, so only the gate modes'
    own exemptions pass. `open` stays open.
  - The retracted key cannot act as owner, because its key proofs fail.
  - Nobody can take the device over remotely: neither ingest nor the owner
    claim registers a new owner while a retracted one is stored. A device gets a
    new owner only by reinstalling its firmware, which wipes AdminDB. The
    first person to sign in on it afterwards becomes the owner, as on a fresh
    device ([Bootstrap and Owner](pq_access_gating.done.md#bootstrap-and-owner)).
    That step needs physical access, which a thief who retracted the owner
    remotely does not have.

---

## Clients

- **Closing an account** is a deliberate, irreversible action, in Settings
  and at the end of a recovery. The client:
  1. shows what closing costs — every contact has to be met again, and the
     history stays readable but nothing more can be sent;
  2. signs the statement and ingests it;
  3. offers to retire the account's community backup on chain (`revokeSecret`),
     off by default (see Community backup below);
  4. signs out. Deleting the local data is offered, not done by default.
- **The retraction set.**
  - Every client syncs `identity_retractions` and keeps a persisted local set
    that only grows.
  - A retracted identity stays retracted locally, even if a server later serves a
    view without it.
  - The client records, per identity, when it first learned of the retraction.
- **A contact's retraction:**
  - The dialog shows one fixed banner — "This account was closed by its owner"
    — and the composer is disabled.
  - The contact's name comes from the local contact record, never again from
    the card.
  - Messages, edits and deletions from the identity that this client first
    sees after it learned of the retraction are shown labelled, not applied
    silently. Earlier history stays as it was.
  - The banner says what to do: do not trust new messages, change anything
    secret shared with that account, meet in person to reconnect.
- **Community backup:**
  - an owner whose guardian or node operator is retracted sees that holding as
    lost in the roster, with a reshare prompt;
  - a guardian sees "owner closed their account" on the holding and keeps it,
    since the owner may still recover the old account's data; it drops the
    holding when the backup is retired on chain (`pq_recovery_shares` § Dying);
    the owner chooses which when closing, retiring being off by default.
- **No successor.** A new account is a new identity. Contacts connect to it in
  person, as with any account.

---

## What retraction does not do

- It does not delete history, messages or files.
- It does not point anywhere: no "my new account is".
- It is not reversible, by anyone.

---

## Later

- **Notice without the key.** A retraction statement pre-signed when the
  account is created, held by the account's guardians in shares, and
  published by them when the owner has lost every device. This needs a
  pending state and an objection by the old key, because guardians could
  otherwise kill an account the owner still uses.
- **Public anchor.** An optional commitment on chain, to give a retraction a
  time no server controls.
- **Reports by others.** Signals about someone else's account, weighted by
  each viewer's own trust graph and never enforced network-wide.

---

## References

- [Access Gating](pq_access_gating.done.md): write gate, read sessions, owner
  bootstrap and claim.
- [Vouch Tokens](pq_vouch_tokens.in_progress.md): the chain-distance query.
- [User](pq_user.done.md): user cards.
- [Recovery shares](pq_recovery_shares.proposed.md): § Dying.
- [Integrity](../invariants/02_integrity.md): signed rows.

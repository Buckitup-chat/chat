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

The same key signs proof-of-possession challenges. Those need a domain of
their own, so that a server cannot obtain a retraction signature by sending
a crafted challenge; `pq_pop_binding.proposed.md` proposes it. Until then
the separation rests on the framed payload not being valid UTF-8, which
challenges are encoded as.

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

- **Verification, everywhere.** HTTP ingest, peer sync and clients accept a
  row only when **both** hold: `user_hash` is the hash of `sign_pkey`, and
  `sign_b64` verifies under `sign_pkey`. A signature check alone proves
  nothing, because the row names its own key: anyone could sign with their
  own key and put a victim's `user_hash` beside it.
- **HTTP ingest.**
  - `/ingest` and `/ingest_each` accept `insert` for `identity_retractions`; no
    card is needed.
  - There is **no** proof-of-possession check: the statement carries its own
    signature, and replaying it is harmless.
  - The insert is never chain-gated, in any mode, like a `user_card` insert.
    Anyone can deliver a retraction, a guardian or a new account included.
  - `update` and `delete` are refused (insert-only, see [Semantics](#semantics)).
  - The shape's conflict fingerprint is `user_hash`. A second valid statement
    for an already retracted identity answers `exists` with
    `conflicted: false`, and clients count it as delivered. Two devices of
    one owner closing the account at once both succeed.
  - The same rate limits as card ingest apply. A throwaway key can sign a
    retraction of itself, as it can publish a card today. Rows are never
    deleted, so these limits are the only bound on the table.
- **Peer sync.**
  - `sync_persist(:insert, …)` verifies as above and inserts, keeping a stored
    row; `:update` and `:delete` are ignored.
  - The row has no required parents.
- **Reads.** `identity_retractions` joins the read-exempt shapes beside
  `user_card` and `vouch_token`. Clients read the whole table. Retractions are
  rare, and a whole-table read tells the server nothing about whose
  retraction a client cares about.

---

## Server enforcement

- **Writes.**
  - Every write a server accepts over HTTP refuses a retracted acting identity,
    **in every gate mode, `open` included, and for the owner too**. That covers
    `/ingest`, `/ingest_each` per row, and `PUT /electric/v1/file_chunk`.
    This amends the decision order of [Access Gating](pq_access_gating.done.md):
    the retraction check comes before "`open` allows" and before "the owner is
    always approved".
  - The one exception is an `identity_retractions` insert itself, accepted
    again so that a replay is idempotent.
  - The **acting identity** is the one whose key proved possession for the
    request: the PoP signer, or the uploader for a chunk. It is not whichever
    field a shape's gate names. An `origin` update, for example, is gated on
    `origin_hash` but proved by the origin owner's key, and the owner is the
    identity checked.
  - One unconditional helper does it, with no gate-mode branch: an indexed
    lookup by `user_hash`. It runs where the acting identity is known: in each
    PoP verifier (`*_allowed`, the review right candidates'
    `right_candidate_check`) and in the chunk upload. It belongs nowhere inside
    `WriteGate.enforce/2`, which never runs in `open` mode.
  - The answer is `403 {"error": "identity_retracted"}` on `/ingest` and as
    the row's error on `/ingest_each` (whose batch status becomes 403).
    `ElectricController` maps it beside `not_in_trust_chain`.
  - Clients treat `identity_retracted` as permanent and drop the identity's
    queued writes instead of retrying them.
  - Peer sync does **not** refuse a retracted identity's rows. A server that
    refused rows another server accepted would never converge with it. Clients
    classify those rows instead.
- **Key proofs.**
  - `KeyProof.prove/3` refuses a retracted identity with its own reason,
    `:identity_retracted`, answered as `403 {"error": "identity_retracted"}`.
    It is not `:unknown_user`, which tells a client to re-ingest its card and
    retry.
  - Read sessions already issued to the identity are dropped when the
    retraction arrives.
  - Every other place that grants a role from an identity's key refuses a
    retracted one as well. In particular, the admin sandbox does not grant
    the owner role to a retracted owner's key file.
- **Reads stay as the gate modes define them**
  ([Access Modes](pq_access_gating.done.md)).
  - In `open` and `guarded`, reads are anonymous, so a retracted identity
    reads like anyone else. Refusing it there would need every reader to prove
    a key. Even then, the holder of a retracted key would simply read under a
    new account, since neither mode checks a chain for reads.
  - In `trust`, a gated shape needs a read session, which a retracted identity
    can no longer open. The read-exempt shapes (`user_card`, `vouch_token`,
    `identity_retractions`) stay readable by anyone, as for every reader.
- **Trust graph.** The chain-distance query skips every vouch whose issuer is
  retracted, at every hop, and refuses a retracted subject: a retracted identity
  neither grants nor holds a place in any chain. A retraction carries no scope,
  so every insert, local or synced, flushes the whole resolved-chain cache.
- **Device owner.** A retracted owner must not leave the device more open than
  before, or a thief holding the owner's key would open it by retracting.
  - The gates treat a retracted owner as present but unable to vouch: in
    `guarded` and `trust` nobody's chain reaches it, so only the gate modes'
    own exemptions pass. `open` stays open.
  - The retracted key cannot act as owner: its key proofs fail, and the admin
    UI refuses it.
  - Nobody can take the device over remotely: neither ingest nor the owner
    claim registers a new owner while a retracted one is stored (`put_new`
    keeps the stored owner).
  - A device gets a new owner only after a firmware reinstall that wipes
    AdminDB. Wherever the platform keeps AdminDB, the reinstall must clear it.
    The wipe resets more than the owner:
    - the device gets a new server identity (SyncBot key), so peers vouch for
      it again;
    - the gate mode returns to `open`.
  - Who becomes owner after the reinstall is [open question 1](#open-questions).

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
  - On every connect, the retraction set syncs to up-to-date **before** the
    client applies any other shape's catch-up. A contact back after a week
    offline therefore knows of a retraction before it sees the messages that
    followed it.
- **A contact's retraction:**
  - The dialog shows one fixed banner — "This account was closed by its owner"
    — and the composer is disabled.
  - The contact's name comes from the local contact record, never again from
    the card.
  - New messages from the identity that this client first sees after it
    learned of the retraction are shown, labelled.
  - Edits and deletions it sees after that point are **not applied**. Each is
    shown as a labelled note beside the revision it would replace, so earlier
    history stays as it was.
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

## Open questions

1. Who becomes owner after the reinstall? The first sign-in over the network
   registers one, and a thief who watches `/electric/v1/device_identity` can be
   first, as can any client that reconnects and re-ingests its card. Closing
   that needs registration on a freshly reset device to come from the device
   itself: the local console, a setup window opened by a button, or a USB key.

---

## References

- [Access Gating](pq_access_gating.done.md): write gate, read sessions, owner
  bootstrap and claim.
- [Vouch Tokens](pq_vouch_tokens.in_progress.md): the chain-distance query.
- [User](pq_user.done.md): user cards.
- [Recovery shares](pq_recovery_shares.proposed.md): § Dying.
- [Integrity](../invariants/02_integrity.md): signed rows.

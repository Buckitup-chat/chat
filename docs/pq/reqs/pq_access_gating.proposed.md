# PQ API Access Gating

## Purpose

Control who can write data through the Electric ingest API. The first user registers unconditionally and becomes the **owner**. All subsequent users are subject to the active access mode. Shape reads remain open — all synced data is encrypted, so read access leaks nothing useful.

---

## Access Modes

| Mode | New user_card ingest | Other ingest (existing users) | Shape reads |
|------|---------------------|-------------------------------|-------------|
| `open` | Anyone | Anyone with valid PoP | Open |
| `contacts` | Owner's optical-handshake contacts auto-approved | Approved users only | Open |
| `invite` | Owner must explicitly approve each `user_hash` | Approved users only | Open |
| `locked` | Rejected | Approved users only | Open |

Default mode: `open` (preserves current behavior).

### Mode transitions

Any mode can transition to any other mode. Changing mode does not revoke already-approved users — it only affects how *new* users get approved.

---

## Owner

The first `user_card` successfully ingested when no owner exists becomes the owner. The owner's `user_hash` is persisted in AdminDB.

- Owner is always approved regardless of mode.
- Owner can change the access mode.
- Owner can explicitly approve or revoke any `user_hash`.
- There is exactly one owner. Ownership transfer is out of scope for this requirement.

---

## Contacts Whitelist

In `contacts` mode, the owner's trusted contacts (established via the [optical handshake flow](../flows/pq_optical-handshake.livemd)) are automatically whitelisted.

### Flow

1. Owner performs optical handshake with a peer — exchanging ECC public keys and proving key ownership via signed nonces.
2. Owner's device stores the peer's `user_hash` + `ecc_pub` as a ContactCandidate.
3. When the peer's UserCard appears (via shape sync), the candidate is verified (matching `user_hash` and `contact_pkey`) and promoted to a trusted Contact.
4. Trusted Contact's `user_hash` is added to the approved set.

### Implications

- Contact trust is directional — the *owner's* contacts are whitelisted, not every user's contacts.
- Revoking a contact (if/when supported) removes the approval.
- Contacts approved this way appear in the approved list alongside explicitly approved users but are tagged as `contact`-sourced so the owner can distinguish them.

---

## Approval List

A persistent set of approved users with their signing public keys:

| Field | Type | Notes |
|-------|------|-------|
| `user_hash` | text | Primary key, `"u_" + hex(SHA3-512(sign_pkey))` |
| `sign_pkey` | binary | ML-DSA-87 public key — the gate verifies PoP signatures directly against this |
| `source` | enum | `owner` / `contact` / `manual` |
| `approved_at` | integer | Unix timestamp |
| `revoked` | boolean | Soft revoke; `false` by default |

Storage: **TBD** — see [Open Questions §4](#open-questions).

Storing `sign_pkey` lets the gate verify the PoP signature against the approved key *before* the ingest reaches the writer — no DB lookup needed. It also means the gate can authenticate requests for any table, not just `user_card` mutations that carry a `user_hash` field.

---

## Gating Mechanics

### Where

A new plug `ChatWeb.Plugs.ElectricAccessGate` in the router, applied to the ingest scope (after `ElectricReadiness`, before `ElectricChallengeInjector`):

```
scope "/" do
  pipe_through ChatWeb.Plugs.ElectricReadiness
  pipe_through ChatWeb.Plugs.ElectricAccessGate   # <-- new

  scope "/" do
    pipe_through ChatWeb.Plugs.ElectricChallengeInjector
    post "/ingest", ElectricController, :ingest
    post "/ingest_each", ElectricController, :ingest_each
  end
end
```

### What it checks

1. **Mode is `open`** → pass through (current behavior).
2. **No owner registered yet** → allow the ingest, let the first `user_card` insert claim ownership (post-ingest hook or writer callback).
3. **Request's `user_hash` is the owner** → pass through.
4. **Request's `user_hash` is in the approved set and not revoked** → pass through.
5. **Mode is `contacts`** → check if `user_hash` is an owner contact; if yes, auto-approve and pass through.
6. **Otherwise** → reject with `403 Forbidden`, body: `{"error": "access_denied", "mode": "<current_mode>"}`.

### Identifying the caller

The ingest request carries a PoP signature (signed challenge). The gate uses the approval list's `sign_pkey` entries to verify who is calling:

1. Extract the challenge + signature from `params["auth"]`.
2. Iterate approved (non-revoked) entries and attempt `ML-DSA-87.verify(challenge, signature, entry.sign_pkey)`.
3. A match identifies the caller and confirms they are approved — proceed.
4. No match among approved entries — check if this is a `user_card` create mutation. If so, extract `sign_pkey` from the mutation payload, compute `user_hash`, and verify the signature against that key. If valid, apply the mode-dependent approval logic (auto-approve in `open`/`contacts`, reject or pend in `invite`/`locked`).

This avoids needing any PostgreSQL lookup — the approval list (wherever stored, see [§4](#open-questions)) is the sole authority.

---

## Server / Bot Access

Servers and bots that ingest data are identified by their `user_hash` the same way human users are. They must be approved through the same mechanism — either as an owner contact or via explicit manual approval.

No separate "API key" or "server token" concept. The PQ PoP flow is the universal auth.

---

## Owner UI

### Minimum viable

An admin endpoint or LiveView page where the owner can:

1. See the current access mode.
2. Change the mode.
3. See the approved list (with source tags).
4. Manually approve a `user_hash`.
5. Revoke an approved `user_hash`.

### Location

Under the existing Electric sandbox area (`/electric/admin`) or a new route. Gated by owner PoP — only the owner's identity can access it.

---

## Challenge / Ingest Flow with Gating

```
Client                          Server
  |                                |
  |-- GET /challenge ------------->|  (unchanged)
  |<-- {challenge_id, challenge} --|
  |                                |
  |-- POST /ingest --------------->|
  |   {auth: {challenge_id, sig}, |
  |    mutations: [...]}           |
  |                                |
  |   [ElectricReadiness]          |  DB + Electric up?
  |   [ElectricAccessGate]         |  Mode check:
  |     - open? pass               |    - open → pass
  |     - no owner? pass + claim   |    - no owner → pass, post-ingest claim
  |     - approved? pass           |    - approved → pass
  |     - contact? auto-approve    |    - contact in contacts mode → approve + pass
  |     - else? 403                |    - else → 403
  |   [ChallengeInjector]          |
  |   [ElectricController.ingest]  |  PoP verify + writer
  |                                |
  |<-- {txid} or error ------------|
```

---

## Status

Proposed.

## Open Questions

1. Should the owner be able to delegate approval rights to other approved users?
2. Should there be a "pending" state where unapproved users' requests are queued rather than rejected?
3. Should mode be configurable via environment variable for initial deployment, or only through the owner UI?
4. **Where to store the approval list (and owner identity)?**

   | Option | Pros | Cons |
   |--------|------|------|
   | **CubDB (AdminDB)** | Already exists, fast reads, no schema migration. Gate reads are local in-memory lookups. | Single-drive, no built-in replication. Lost if AdminDB drive fails. |
   | **PostgreSQL (non-Electric table)** | Lives alongside PQ data, survives drive swaps if on main DB. Can participate in PG logical replication between main ↔ internal. | Adds a table that must not be exposed via Electric shapes. Gate now depends on PG being up (but it already does via `ElectricReadiness`). |
   | **Both (CubDB primary, PG backup)** | CubDB for fast gate checks, PG as durable backup. Restore from PG if AdminDB is lost. | Two sources of truth to keep in sync. |

   Sub-question: should the approval list be **replicated to the backup drive**? On the platform, each USB drive gets its own PG instance with logical replication between main and internal. If the approval list is in PG, it could ride that replication for free. If it's in CubDB, backup requires explicit copy logic (AdminDB is currently single-drive).

   The owner `user_hash` + `sign_pkey` and the access mode setting have the same storage question.

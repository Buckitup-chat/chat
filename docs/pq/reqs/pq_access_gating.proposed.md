# PQ API Access Gating

## Purpose

Control who can write data through the Electric ingest API. The first user registers unconditionally and becomes the **owner**. All subsequent users are subject to the active access mode. Shape reads remain open — all synced data is encrypted, so read access leaks nothing useful.

---

## Access Modes

| Mode | New user_card ingest | Other ingest (existing users) | Shape reads |
|------|---------------------|-------------------------------|-------------|
| `open` | Anyone | Anyone with valid PoP | Open |
| `contacts` | Owner's optical-handshake contacts auto-approved | Approved users only | Open |
| `trust` | Auto-approved if trust score ≥ threshold | Trust-gated (see [Trust Metrics](#trust-metrics)) | Open |
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

## Trust Metrics

In `trust` mode, access decisions are driven by a computed trust score rather than a binary approved/rejected state. The owner sets a threshold; users above the threshold can ingest, users below are rejected (or pended, see [Open Questions §2](#open-questions)).

### Industry Approaches

Several established models inform how trust can be computed in a decentralized, partially-offline system like BuckitUp:

#### 1. PGP Web of Trust (Vouching)

The classic decentralized trust model. Users vouch for each other by signing keys. Trust propagates along chains: if Alice trusts Bob and Bob trusts Carol, Alice extends partial trust to Carol. BuckitUp's optical handshake already establishes exactly this kind of directional, cryptographically-verified trust link.

**Fit for BuckitUp:** Natural extension of existing contacts. Each approved user could vouch for others (not just the owner), creating a trust graph where trust attenuates with distance. Owner's direct contacts get the highest trust; contacts-of-contacts get less; and so on.

#### 2. EigenTrust (Global Reputation from Local Trust)

Developed for P2P networks. Each peer assigns local trust values to peers it has interacted with. The algorithm computes a global trust score via iterative matrix multiplication (power iteration over a trust matrix), where each peer's opinion is weighted by their own global trust. The eigenvector of the trust matrix gives stable global scores.

**Fit for BuckitUp:** Could aggregate per-user vouches into a single global score without requiring centralized authority. Computable locally from the trust graph. Handles the "vouching for a bad actor" problem — a vouch from a low-trust user carries little weight.

#### 3. NIST SP 800-207 Zero Trust / Continuous Evaluation

NIST's framework evaluates trust continuously across five domains: identity, device, network, workload, and data. Access is never permanently granted — it's re-evaluated per request based on contextual signals (device posture, behavior patterns, anomaly detection).

**Fit for BuckitUp:** The "continuous" aspect maps to per-ingest evaluation rather than one-time approval. Behavioral signals (ingest frequency, data volume, time-of-day patterns) can feed the trust score so it changes over time.

#### 4. Vouchsafe Zero-Infrastructure Capability Graph (ZI-CG)

A 2026 model designed specifically for offline and disconnected environments. Trust is represented as self-contained, signed capability tokens (Ed25519 + JWT) whose validity is determined by local, deterministic evaluation — no online authority required. Supports scoped delegation and explicit revocation.

**Fit for BuckitUp:** Highly aligned with BuckitUp's offline device scenario. Trust tokens could travel with the data itself, allowing the gate to evaluate trust even when disconnected from the original trust authority. The existing PQ PoP signatures could serve as the cryptographic substrate.

### Proposed Trust Score Components

A composite trust score computed from weighted signals:

| Signal | Description | Weight (example) |
|--------|-------------|-------------------|
| `verification_level` | How the user was verified: optical handshake (highest), contact-chain, manual approval, open registration | High |
| `vouches` | Number and quality of vouches from other trusted users, weighted by voucher's own trust score (EigenTrust-style) | High |
| `chain_distance` | Shortest path in the trust graph from the owner to this user (1 = direct contact, 2 = contact-of-contact, etc.) | Medium |
| `tenure` | Time since first successful ingest (longer = more trusted) | Low |
| `interaction_consistency` | Regularity and pattern of ingest activity — sudden spikes or long dormancy reduce score | Low |
| `revocation_history` | Whether the user was ever revoked and re-approved | Negative |

### Approval List Extension

In `trust` mode, the approval list gains additional fields:

| Field | Type | Notes |
|-------|------|-------|
| `trust_score` | float | Computed composite score, 0.0–1.0 |
| `vouched_by` | list | `user_hash` values of users who vouched for this user |
| `last_evaluated` | integer | Unix timestamp of last trust re-evaluation |

### Trust Threshold

The owner sets a threshold (0.0–1.0) via the admin UI. Default: **0.5**.

- Users at or above the threshold can ingest.
- Users below are rejected with `403` and body `{"error": "trust_below_threshold", "score": <score>, "threshold": <threshold>}`.
- The owner can override: explicitly approve a user regardless of score, or explicitly revoke a user regardless of score.

### Vouching Mechanics

When any approved user with `trust_score ≥ vouch_threshold` (configurable, default = owner's threshold) vouches for another user:

1. A signed vouch attestation is created (voucher's `sign_pkey` signs the vouchee's `user_hash`).
2. The vouchee's `vouched_by` list is updated.
3. Trust score is recomputed for the vouchee (and transitively affected users if using EigenTrust).

Vouching is directional and non-transitive by default — Alice vouching for Bob does not mean Alice vouches for everyone Bob vouches for. Transitive trust is handled by the score computation (chain distance + EigenTrust weighting), not by the vouch itself.

### Recomputation

Trust scores are recomputed:
- On new vouch or vouch withdrawal.
- On revocation or un-revocation of any user (affects graph topology).
- Periodically (configurable interval) for behavioral signals (tenure, interaction_consistency).

Recomputation is local — no external service needed.

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
6. **Mode is `trust`** → compute or retrieve cached trust score for `user_hash`; if score ≥ threshold, pass through; if below, reject with `403` and `{"error": "trust_below_threshold", "score": <score>, "threshold": <threshold>}`.
7. **Otherwise** → reject with `403 Forbidden`, body: `{"error": "access_denied", "mode": "<current_mode>"}`.

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
  |     - trust? score check       |    - trust mode → score ≥ threshold → pass
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

5. **Which trust score algorithm?**

   | Algorithm | Pros | Cons |
   |-----------|------|------|
   | **Simple weighted sum** | Easy to implement, transparent to the owner, deterministic. | No transitive trust propagation — each user scored in isolation. |
   | **EigenTrust** | Mathematically sound global reputation from local vouches. Handles sybil-adjacent attacks (low-trust vouches carry low weight). | Iterative computation; complexity grows with user count. May be overkill for small deployments. |
   | **Graph distance only** | Trivial to compute from the trust graph. Intuitive (closer to owner = more trusted). | Ignores vouch quality — one direct contact isn't the same as another. |
   | **Hybrid (distance + weighted vouches)** | Balances simplicity with quality signals. Distance sets the base, vouches adjust within that band. | Two parameters to tune (distance decay, vouch weight). |

6. **Should trust scores be visible to users?** Transparency aids debugging ("why was I rejected?") but also reveals the scoring model, which could be gamed. Options: visible to owner only, visible to each user for their own score, or fully opaque.

7. **Should `trust` mode coexist with `contacts`?** The `contacts` mode auto-approves optical-handshake contacts with implicit full trust. In `trust` mode, should optical-handshake contacts still get automatic high trust, or should all users go through the same scoring pipeline?

8. **Offline trust evaluation.** The Vouchsafe ZI-CG model suggests trust tokens that are self-verifiable offline. Should vouch attestations be structured as self-contained signed tokens (similar to Vouchsafe's capability tokens) so the gate can evaluate trust without any live lookups — just the token chain?

---

## References

- [PGP Web of Trust](https://www.geeksforgeeks.org/computer-networks/what-is-web-of-trust/) — decentralized trust via key signing chains
- [EigenTrust Algorithm](https://dl.acm.org/doi/10.1145/775152.775242) — Kamvar, Schlosser & Garcia-Molina, WWW 2003. Global reputation scores from local trust via power iteration
- [NIST SP 800-207 Zero Trust Architecture](https://www.paloaltonetworks.com/cyberpedia/what-is-nist-sp-800-207) — continuous trust evaluation across identity, device, network, workload, data
- [Vouchsafe ZI-CG](https://arxiv.org/abs/2601.02254) — Kuri 2026. Zero-infrastructure capability graph for offline identity and trust using Ed25519 + signed JWTs
- [Trust Score-Based Access Control for ZTA](https://www.researchgate.net/publication/395226702) — composite trust scoring applied to zero trust access decisions
- [EigenTrust + Zero Trust (EDR application)](https://arxiv.org/pdf/2203.09325) — combining EigenTrust with endpoint signals for network security
- [Dynamic Decentralized Reputation](https://cheqd.io/blog/dynamic-decentralized-reputation-for-the-web-of-trust-what-we-can-learn-from-the-world-of-sports-tinder-and-netflix/) — Elo-style per-domain reputation scores for verifiable credentials

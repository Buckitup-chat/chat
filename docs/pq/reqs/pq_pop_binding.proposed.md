# PoP Binding — purpose and audience in challenge signatures

## Purpose

Every proof of possession (PoP) in the system signs the server's challenge
string and nothing else. A signature made for one server therefore works on
any other server that issued the same challenge, and a signature made for one
purpose works for any other purpose. This document proposes binding each PoP
signature to **what it authorises** (purpose) and **whom it is for**
(audience), under a fixed domain tag.

Status: proposed, for team discussion. Nothing here is implemented.

---

## Current behaviour

The challenge protocol itself is specified in
[Proof of Possession](../invariants/01_proof_of_possession.md); in short:

- **Challenge.** `GET /electric/v1/challenge` returns `challenge_id` and
  `challenge`: 32 random bytes as 64 lowercase hex characters, single use, 60 s
  (`Chat.Challenge`). It is not tied to a requester, a purpose or an audience.
- **Signature.** The signer signs the UTF-8 bytes of `challenge` with its
  ML-DSA-87 `sign_skey`, with no prefix and no context.
- **Verification.** The verifier checks the signature over the bare challenge
  against the claimed user's `sign_pkey`.

| Purpose | Signers | Verifier |
|---|---|---|
| read session | web client `src/lib/data/readSession.ts`; node `ReadSessionClient.open/2` | `Chat.Pq.KeyProof.prove/3` (from `ReadGate.open_session/4`) |
| ingest | web client `api.ingestWithAuthEach`; node `SyncBotCardPusher.push/1`; sandbox API clients | `IngestPop.context/1`, then each shape's `*_allowed` check (`Chat.Data.*.Validation`, 16 call sites) |
| owner claim | web client `src/lib/data/deviceOwner.ts` | `Chat.Pq.KeyProof.prove/3` via `OwnerClaimController` |

The same `sign_skey` also signs canonical row payloads (`Integrity.signature_payload/1`)
and key certificates (`crypt_cert`, `contact_cert`).

---

## Problems

1. **Relay.** A host R that a signer N talks to can fetch a challenge from
   another server D, hand it to N as its own, and post N's signature to D.
   - Concretely: R answers a LAN probe, so node N adds it as a peer. N pushes
     its SyncBot card to R (`SyncBotCardPusher.push/1`) and signs whatever R
     returns as a challenge. R obtains a read session on D as N's SyncBot,
     wherever D has vouched for N.
   - The same works for a malicious server relaying a user's signature to
     another device.
2. **Purpose confusion.** An ingest PoP, a read-session PoP and an owner
   claim have the same pre-image. A signature collected for one is accepted
   as the others. For example, a host that collected a user's ingest proof
   posts it to an ownerless device's `owner_claim` and makes that user the
   owner of a device they never signed in on.
3. **Shape not covered.** A read-session request names a `shape` that the
   signature does not cover.
4. **Domain separation by accident.** Row payloads and challenge strings are
   kept apart today only by encoding.
   - Every row payload carries a length frame such as `00 00 00 82`, which is
     not valid UTF-8, and challenges are signed as UTF-8 strings.
   - A signer that ever decodes a challenge (hex or base64) before signing,
     or a change in hash lengths, would let a server obtain a signature over
     an arbitrary row.
   - No current path does this; nothing prevents it.

---

## Threat model

**In scope:**
- a peer or server the signer talks to, that relays challenges and signatures
  to a third party;
- a server that collects signatures for one purpose and uses them for another.

**Out of scope:** an active man-in-the-middle on a plain-HTTP connection. It
sees the bearer token a legitimate read session returns, whatever the
signature binds; only a secure channel defeats it (see [Future: channel
binding](#future-channel-binding)). Spoofing a name or address on the LAN (mDNS,
DNS, ARP) makes the attacker the endpoint the signer dialed, so it is the same
man-in-the-middle and equally out of scope.

---

## Design

### Pre-image

```
pop_preimage = "buckitup/pop/v1" || 0x00 || purpose || 0x00 || audience || 0x00 || challenge
```

All four parts are ASCII; `0x00` separates them and occurs in none.

- **Domain tag** `buckitup/pop/v1`: its first byte, `b` (`0x62`), differs from
  the first byte of every row payload, `0x00` (the high byte of a `u32`
  length). The two signature spaces are disjoint by construction.
- **Version.** A format change bumps the tag (`v2`). A verifier accepts
  exactly one version.

### Purpose

| Purpose string | Used by |
|---|---|
| `read_session:<shape>` | `POST /electric/v1/read_session`; `<shape>` is the requested shape name exactly as sent |
| `ingest` | `POST /electric/v1/ingest`, `POST /electric/v1/ingest_each` |
| `owner_claim` | `POST /electric/v1/owner_claim` |

The verifier derives the purpose from the endpoint it serves and the request
it received. It never reads the purpose from the client.

### Audience

The audience is the **origin the signer is about to send the request to**:
`scheme://host[:port]` as the WHATWG URL `origin`.
- scheme and host are lowercase;
- the default port is omitted;
- IPv6 is bracketed;
- there is no path and no trailing slash.

| Signer | Audience source |
|---|---|
| Web client | `new URL(ELECTRIC_API_URL, location.href).origin`: `ELECTRIC_API_URL` may be relative (`/api` behind the Vite dev proxy), and the audience is then the page's origin, which a dev backend lists in `POP_AUDIENCES` |
| Node (`ReadSessionClient`, `SyncBotCardPusher`) | the origin of `peer_url`, the address the node itself dialed |

Examples: `HTTP://Device.local:80/electric/v1` → `http://device.local`;
`https://buckitup.xyz:443` → `https://buckitup.xyz`;
`http://[fe80::1]:4000/x` → `http://[fe80::1]:4000`.

The signer sends the audience it signed with the request, as `audience` next to
`challenge_id` and `signature` (inside `auth` for ingest). The verifier:

1. checks that the audience is in its **self-audience set**, and answers
   `401 {"error": "wrong_audience"}` when it is not, so a misconfigured proxy
   shows as such;
2. verifies the signature once, over the pre-image built with that audience.

A relay cannot change the audience without breaking the signature, and the
signer named the relay's origin, which is not in the verifier's set. The
`Host` header plays no part: whoever makes the request chooses it, the relay
included.

### Self-audience set

Every origin under which this server is legitimately reached:

1. the configured public URL of the endpoint (`ChatWeb.Endpoint` `url`,
   `PHX_HOST`);
2. on a device: each non-loopback interface address × each listening port,
   and `<hostname>.local` (mDNS) × each port;
3. `POP_AUDIENCES`: a comma-separated list of extra origins, for reverse
   proxies, port forwards and tunnels.

The set is computed at boot and refreshed when interfaces change (DHCP).

### Signer rules

- Sign only a challenge matching `^[0-9a-f]{64}$`; refuse anything else.
- Build the pre-image from the purpose of the request being made and the
  origin of the URL it is posted to, never from values the server supplied.
- One helper per stack:
  - `popSignature(purpose, audience, challenge)` in `src/lib/pq/`;
  - `Chat.Pq.Pop.sign/4` for nodes.
- No caller builds the bytes by hand.

### Verifier rules

- `Chat.Pq.Pop.verify(purpose, audience, challenge, signature, sign_pkey)` replaces
  every bare `EnigmaPq.verify(challenge, signature, sign_pkey)` on a challenge:
  - `KeyProof.prove` gains purpose and audience arguments;
  - `IngestPop.context/1` carries `purpose: "ingest"`, and the 16 `*_allowed`
    checks call `Pop.verify` with it.
- The challenge stays single use. The signature now proves possession of the
  key, for this purpose, to this server, within 60 s.

### Rollout

- One coordinated release of backend, web client and node code.
- The project owes no backward compatibility. An old client or node gets
  `401` until updated, and no server accepts both formats.
- Nodes upgrade independently, and some stay offline for long periods. Two
  nodes on different versions refuse each other's proofs, so sync between them
  stops until both run the new version (see open question 6).

### Test vector

```
purpose   = "read_session:user_storage"
audience  = "http://192.168.1.20:4000"
challenge = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

pop_preimage (131 bytes, hex) =
6275636b697475702f706f702f763100726561645f73657373696f6e3a757365725f73746f7261676500
687474703a2f2f3139322e3136382e312e32303a343030300030313233343536373839616263646566
303132333435363738396162636465663031323334353637383961626364656630313233343536373839
616263646566
```

ML-DSA-87 signatures are randomised, so the vector pins the pre-image. Both
stacks test that they produce these bytes, and that a signature by either
verifies in the other.

---

## Alternatives considered

| Alternative | Why not |
|---|---|
| Audience = the verifier's `device_id` or SyncBot `user_hash`, as the signer learned it | The signer learns it from the host it talks to; a relay reports the target's identity as its own. |
| Audience = the request's `Host` header | The relay makes the request and sets `Host` to whatever the signer named. |
| Mutual authentication: the server signs the client's nonce first | Relayable without channel binding: the relay forwards the nonce to the target and the answer back. It also needs the signer to know the expected server key in advance, which LAN discovery does not provide. |
| Bind the challenge to the requester's IP at issuance | Breaks behind NAT, proxies and mobile networks, and a relay can request the challenge from its own address anyway. |

---

## Future: channel binding

The audience defeats a relay, not a man-in-the-middle on the same connection.
A secure transport would close that:
- TLS with a server certificate bound to the SyncBot key and pinned on first
  contact; or
- a Noise handshake between nodes.

The PoP would then sign the channel's exporter value instead of the audience,
and the self-audience set would disappear. This proposal is the step before
that, not a substitute for it.

---

## Open questions

1. Is the self-audience set workable on devices? It needs the interface list,
   the mDNS name and the listening ports, and it must cope with an address
   change between challenge and request.
2. Should `read_session:<shape>` be narrowed further, to the shape's `where`
   parameters, or is the shape name enough?
3. Should the challenge endpoint return the purposes it will accept, so a
   client can fail early? The server can always reject anyway.
4. Do the sandbox API clients get the same helper, or are they removed from
   production builds instead?
5. When does node-to-node traffic move to a secure transport, which makes the
   audience redundant?
6. Should verifiers accept the bare-challenge format for a transition window,
   so that nodes upgraded at different times keep syncing? That reopens the
   relay for the window.

---

## References

- [Proof of Possession](../invariants/01_proof_of_possession.md): the
  challenge protocol this proposal extends.
- [Access Gating](pq_access_gating.done.md): read sessions, owner bootstrap and
  claim, SyncBot card push.
- [Vouch Tokens](pq_vouch_tokens.in_progress.md): the read scopes a relayed
  session would obtain.
- `Chat.Data.Integrity.signature_payload/1`: row pre-images.

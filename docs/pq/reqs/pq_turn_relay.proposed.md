# PQ TURN Relay

## Purpose

The optical handshake v2 (`chat-frontend/docs/task-handshake-pq2.md`)
confirms a contact over a WebRTC data channel between the two phones. On one
Wi-Fi the phones reach each other directly. On two networks, for example both
on mobile data behind carrier-grade NAT, neither a direct path nor a
STUN-discovered one connects, and the handshake ends *optically verified*
instead of *confirmed*.

A TURN relay closes that gap. This requirement is the backend's part:

- a relay on our own host, not a third party's;
- an endpoint that hands a client short-lived credentials for it.

Owner decision (2026-10-05): the relay's addresses go into **every** handshake
code next to the phone's own addresses. On one network ICE still prefers the
direct path; across networks the relay carries the channel. No second attempt
and no extra tap.

---

## What the relay sees, and what it cannot do

- **It sees:** two IP addresses, the time, and the size of the traffic.
- **It cannot read the channel:** DTLS runs end to end between the phones.
- **It cannot impersonate either phone:**
  - each phone accepts only the certificate fingerprint it scanned from the
    other's screen;
  - the post-quantum confirmation and the six-digit code both cover those
    fingerprints (handshake spec §4).
- **The worst it can do is drop the channel.** The handshake then ends
  *optically verified*, exactly as with no relay.

So the relay needs availability, not trust.

---

## Architecture

Two parts, on the host that serves the chat backend.

1. **Credential endpoint**, in the chat release: `POST
   /electric/v1/turn_credentials`, authenticated by proof of possession
   (§ Endpoint).
2. **The relay**: its own release on the same host, built on ProcessOne's
   `stun` library (hex `stun`) — not inside the chat BEAM.
   - Every allocation holds a UDP port and a process. A relay under load
     must not take the chat release's file descriptors and schedulers with
     it.
   - It checks the credentials of § Credentials itself, with the secret the
     endpoint signs them with; it never calls the chat release.

### Why the `stun` library, and what it needs around it

- **It covers the transports:** UDP, TCP and TLS listeners. Networks that
  block UDP need TLS, and mobile networks are where the relay matters.
- **It is maintained:** 1.2.23 is from August 2026. ProcessOne ships it in
  ejabberd and builds eturnal, a standalone TURN server, on it.
- **It has the hooks this needs:**
  - `auth_fun`, for credentials of our own format;
  - peer black- and whitelists per listener;
  - `turn_max_allocations` and `turn_max_permissions`.
- **It is Erlang, not C.** TLS goes through `fast_tls`, so OpenSSL; check
  that `fast_tls` builds for the Raspberry Pi target (aarch64) before relying
  on it. ejabberd runs there.

Rel (`elixir-webrtc/rel`) is UDP-only and has had no commit since April 2024.

**What the library does not do, read from its source (`stun.erl`,
`turn.erl`), and what covers each:**

| The library | What covers it |
|---|---|
| Checks a request's peer addresses as a set: one whitelisted address lets every blacklisted one in the same request through | A patch that checks each address on its own, offered upstream. Until it lands, no deployment sets a whitelist |
| Matches an IPv4 peer against a `::ffff:0:0/96` entry as if it were mapped, so that entry blocks every IPv4 peer | The entry is never listed. The relay allocates IPv4 only, and an IPv6 peer, mapped or not, fails its family check |
| `{expired, Pass}` from `auth_fun` only stops a new Allocate; Refresh, CreatePermission and ChannelBind still pass | `auth_fun` refuses an expired credential outright. An allocation then ends within the lifetime last granted to it |
| The `shaper` limits only TCP and TLS clients, never UDP or relayed traffic | Per-source rate limits in the host firewall (nftables) on UDP 3478 and the relay port range |
| No global cap on allocations | The relay port range is the cap; the endpoint's per-address issue limit and the separate release keep an exhausted relay from reaching chat |

---

## Credentials

The scheme is *A REST API For Access To TURN Services*
(draft-uberti-rtcweb-turn-rest-00 §2.2): the relay's `auth_fun` checks it, and
coturn's `use-auth-secret` and eturnal implement the same.

```
username   = "<expiry_unix_seconds>:<tag>"
credential = Base64(HMAC-SHA1(TURN_SECRET, username))
```

- **`tag`** is 16 random bytes in lowercase hex, fresh per issue. It is **not**
  the `user_hash`: the relay's logs and allocations must not name identities.
  The endpoint knows who asked; the relay does not need to.
- **`expiry`** is now + `TURN_TTL_SECONDS` (default 600). A handshake session
  lives 90 s, and its channel closes once the confirmation is exchanged.

Test vector:

```
TURN_SECRET = "buckitup-test-secret"
username    = "1791200000:6f1c2a9d4e8b7a3c0d5e9f1a2b3c4d5e"
credential  = "lpJ4fKChsz/b21/Y2LZCo1ST4gc="
```

---

## Endpoint

```
GET  /electric/v1/challenge             → {challenge_id, challenge, expires_in}
POST /electric/v1/turn_credentials      {user_hash, challenge_id, signature}
     ← 200 {username, credential, ttl, uris}
     ← 401 {"error": "Invalid or expired challenge"}
     ← 401 {"error": "unknown_user"}
     ← 401 {"error": "invalid_signature"}
     ← 429 {"error": "rate_limited", "retry_after": <seconds>}
     ← 503 {"error": "turn_unavailable"}
```

1. **Prove possession.** Proof of possession is one module,
   `Chat.Pq.ProofOfPossession`, for its three callers — ingest, read sessions
   and this endpoint — and owned by none of them. It holds what they do today,
   each on its own:
   - `take(challenge_id, signature_b64)` consumes the challenge and decodes
     the signature, giving `%{challenge, signature}`. Ingest's
     `ChatWeb.Utils.IngestPop.context/1` keeps reading the body's `auth` field
     and calls it.
   - `verify(pop, sign_pkey)` checks ML-DSA-87 over the challenge's UTF-8
     bytes. The shapes' ingest validations call it with the key their
     mutation answers to — the row's own `sign_pkey` for a new `user_card`, the
     stored card's otherwise — where they call `EnigmaPq.verify/3` now.
   - `verify_user(user_hash, challenge_id, signature_b64)` is `take`, the
     `sign_pkey` of a card with `deleted_flag: false`, and `verify`. Its steps
     come out of the `with` chain of `ReadGate.open_session/4`, which then
     calls it as this endpoint does.
   - A deleted identity is `401 unknown_user` on both endpoints, and a
     malformed `user_hash` a `401`, not a `500`; one error mapping for the
     three failures serves both controllers. Ingest's answers do not change.
2. **Issue** the credentials above. `uris` is `TURN_URIS` verbatim, e.g.:

   ```json
   ["turn:buckitup.xyz:3478?transport=udp",
    "turns:buckitup.xyz:5349?transport=tcp"]
   ```

   **Two URIs, not more.** The browser allocates a relay on every URI it is
   given, a phone's code carries at most two relay addresses, and a slow or
   blocked transport holds up address gathering. UDP is the fast path; TLS
   reaches networks that block UDP.

**Not chain-gated, in any mode.** A new user's first optical handshake is how
they enter the trust chain (`pq_access_gating`: an optical-handshake contact is
a vouch at distance 1). Gating the relay on the chain would be circular, like
gating `user_card` ingest. The PoP still requires an ingested `user_card`.

**A rate limit per address, not per identity.** A `user_hash` costs nothing:
card ingest is never gated, so a limit per identity is bypassed by minting
identities. The endpoint limits issues per client IP instead —
`TURN_RATE_PER_IP_HOUR` (default 60) in a sliding hour, in an ETS table owned
by a GenServer, swept like `Chat.Challenge` — and answers `429
{"error": "rate_limited", "retry_after": <seconds>}` past it. The address is
`conn.remote_ip`, with a reverse proxy's forwarded header trusted only from
that proxy. The default is lenient because carrier-grade NAT puts many phones
behind one address; what bounds a determined abuser is the relay's port range
and the host firewall's rate limits (§ The relay).

**`503 turn_unavailable`** when `TURN_SECRET` is not set: a server that runs no
relay. The client proceeds with its own addresses only, which is all a shared
network without client isolation needs.

Routing: in the `/electric/v1` scope next to `/challenge`, **outside**
`ElectricReadiness`, with an `options` route for CORS. The endpoint needs the
database, not Electric: a relay must not go dark while Electric starts. A
database it cannot reach is `503 turn_unavailable`, the documented body.

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `TURN_SECRET` | unset → `503` | The HMAC key of § Credentials. The endpoint and the relay release each read it; the endpoint needs no relay in its own release, so eturnal or coturn can stand in |
| `TURN_URIS` | unset → `503` | Comma-separated list returned as `uris` |
| `TURN_TTL_SECONDS` | `600` | Credential lifetime. A client renews when less than 150 s remain, so a session never outlives its credential |
| `TURN_RATE_PER_IP_HOUR` | `60` | Issues per client IP per hour |
| `TURN_PUBLIC_IP` | required by the relay | `turn_ipv4_address`: the address relays are given out under |
| `TURN_CERTFILE` | required for TLS | The relay's PEM: private key and chain |

The secret lives where `SECRET_KEY_BASE` does: the deploy environment, never
the repository.

---

## The relay

A release of its own, around the `stun` library, with two listeners and
`use_turn`:
- **UDP** on 3478;
- **TLS** on 5349: `tls: true`, and `certfile` one PEM holding the private key
  and the chain. The library passes only `certfile` to `fast_tls`, so the key
  must be in it.

**`auth_fun(User, Realm)`** answers the credential or `<<"">>`, and never
raises — it runs inside the listener for every client:
- `<<"">>` when the realm is not ours, the username does not parse as
  `<expiry>:<tag>`, or the expiry has passed;
- otherwise `Base64(HMAC-SHA1(TURN_SECRET, username))`.

**Options:**
- `auth_type: user`, `auth_realm` the domain.
- `turn_ipv4_address`: `TURN_PUBLIC_IP`, required. The library's default is
  `127.0.0.1`, which would hand out relay addresses nobody can reach, so the
  release refuses to start without it.
- `turn_min_port` / `turn_max_port`: the relay port range, which is also the
  cap on concurrent allocations.
- `turn_max_allocations` 4 per credential: each phone allocates two per
  session.
- `turn_max_permissions` 16. The library counts existing and requested
  addresses together, repeats included, and a peer's code carries up to six;
  a tight limit breaks a permission refresh.

**The host firewall** rate-limits each source on UDP 3478 and the relay port
range — the bandwidth the library does not shape. A handshake moves about
15 KB, a card and an ML-DSA signature each way.

### Which peers a relay may reach

A relay that reaches any address is an open proxy into the networks behind it.
The library refuses a peer that is on the blacklist and not on the whitelist.

**The blacklist, on every deployment:**
- IPv4:
  - `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `127.0.0.0/8`;
  - `169.254.0.0/16`, `172.16.0.0/12`, `192.0.0.0/24`, `192.168.0.0/16`;
  - `198.18.0.0/15`, `240.0.0.0/4`;
- the host's own public address: traffic to it is delivered locally, past the
  firewall.

No IPv6 entries: the relay is IPv4-only, and an IPv6 peer fails the family
check first. No `::ffff:0:0/96` entry in any case (§ Why the `stun` library).

**The whitelist depends on where the server is:**
- **On the internet** (`buckitup.xyz`): empty. The relay serves phones on the
  internet and reaches nothing private.
- **On a BuckitUp device** (a node in an office or a home): the device's gray
  IPs — the private ranges its network profiles give it, which the platform
  repo (`Buckitup-chat/platform`) defines — *minus the device's own
  addresses*: a whitelist overrides the blacklist, so the device itself must
  fall outside it. Phones on one Wi-Fi with client isolation then reach each
  other through the relay.
  - The relay keeps no list of its own. It takes the ranges from the
    platform, as chat's `LanDetector` already takes the LAN range over the
    `chat->platform` bridge (`{:lan_ip_and_mask, pid}` →
    `{:range, {ip, mask}}`), and takes them again when the profile changes.
  - It listens on the device's LAN interfaces only. Its clients can reach the
    LAN anyway; what the whitelist must never open is loopback and the device
    itself.
  - It needs the per-address patch first: without it, a request naming one
    LAN address and `127.0.0.1` passes. Until then a device relays to public
    addresses only.

**Firewall:** open UDP 3478, TCP 5349 and the relay port range.

**Certificate.** On staging the chat release runs behind a reverse proxy and
holds no certificate, and certbot's `live/` directory is root-only. A certbot
deploy hook writes the key and chain into one PEM readable by the relay's user,
and restarts the relay's TLS listener, which drops `fast_tls`'s cached context.
Without it TLS is silently off, and networks that block UDP get no relay.

**Logs:** the log names only the random `tag` from the credential, never a
`user_hash`.

---

## Tests

- **Credential function:** the test vector above. The username carries a
  future expiry and a 32-hex tag, and two issues never share a tag.
- **Controller:** each error row of § Endpoint. A valid PoP returns the
  configured `uris`. With `TURN_SECRET` unset the answer is `503`, and in
  `trust` mode an identity with no vouch still gets credentials.
- **Rate limit:** the 61st issue from one IP in an hour is `429` with
  `retry_after`; another IP is unaffected; an expired entry is swept.
- **`ProofOfPossession`:** the ingest and read-session tests pass unchanged
  through it, and a deleted card is `unknown_user` on both endpoints.
- **The relay's `auth_fun`:** the test vector's credential is accepted before
  its expiry and refused after it; a wrong credential, a wrong realm and a
  username that does not parse are refused, and none raises.
- **Peers:**
  - with an empty whitelist, a permission toward a public IPv4 peer is
    granted and one toward `192.168.1.10` refused;
  - with the platform's range `192.168.1.0/24` (and the patch in),
    `192.168.1.10` is granted; `127.0.0.1` and the device's own address are
    refused, alone and in a request that also names `192.168.1.10`;
  - after the platform reports another range, the old one is refused and the
    new one granted.
- **Expiry:** after the credential expires, a Refresh and a CreatePermission
  on an existing allocation are refused.
- **End to end:** `chat-frontend/sandbox/handshake-pq2/scripts/check.mjs` with
  `PQ2_TURN_URL`, `PQ2_TURN_USER` and `PQ2_TURN_PASS` set from a response of
  this endpoint completes a confirmed handshake through the relay.

## Acceptance

- Two phones, both on mobile data, with the app pointed at staging: both
  show "Contact confirmed" and the same six digits.
- The same two phones on one Wi-Fi: confirmed over the direct path — the
  selected ICE pair is host to host (`chrome://webrtc-internals`).
- A credential used after its expiry is refused by the relay, for a Refresh
  as for a new allocation.
- A relay request toward `127.0.0.1`, the host's private network, the host's
  own public address or any IPv6 address is refused, and a TCP relay request
  (RFC 6062) is refused outright; a request toward a phone's public IPv4
  address is granted.
- On a BuckitUp device: two phones on one Wi-Fi with client isolation
  confirm through the relay, with no relay configuration on the device.
- `turns:buckitup.xyz:5349` completes a TLS allocation after a certificate
  renewal.

---

## Status

Proposed.

## Open questions

1. **TURN over TLS on port 443.** Some networks allow only 443. Sharing it
   with Phoenix takes an ALPN multiplexer in front of both; deferred until a
   network that needs it shows up.
2. **IPv6 relay addresses**, when the host has IPv6: whether to relay over
   IPv6 at all, and the client's limit of two IPv6 addresses per code.
3. **Nodes on the internet.** Whether a node with a public address runs a
   relay for its users; its configuration is `buckitup.xyz`'s.

## References

- `chat-frontend/docs/task-handshake-pq2.md` — the handshake that uses the relay.
- [PQ access gating](pq_access_gating.in_progress.md) — why the endpoint is not chain-gated.
- [Proof-of-Possession](../invariants/01_proof_of_possession.md) — the ingest PoP that `Chat.Pq.ProofOfPossession` takes over.
- `Buckitup-chat/platform` — the device network profiles the relay's whitelist comes from.
- draft-uberti-rtcweb-turn-rest-00 — the credential scheme.

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

Two parts, both in the chat release.

1. **Credential endpoint**, in Phoenix: `POST /electric/v1/turn_credentials`,
   authenticated by proof of possession (§ Endpoint).
2. **The relay**: ProcessOne's `stun` library (hex `stun`), started by the
   release.
   - Its listeners take UDP on 3478 and TLS on 5349.
   - Its `auth_fun` checks the credentials of § Credentials in-process,
     with the same secret the endpoint signs them with.

### Why the `stun` library

- **It covers the transports:** UDP, TCP and TLS listeners. Networks that
  block UDP need TLS, and mobile networks are where the relay matters.
- **It is maintained:** 1.2.23 is from August 2026. ProcessOne ships it in
  ejabberd and builds eturnal, a standalone TURN server, on it.
- **It has the hooks this needs:**
  - `auth_fun`, for credentials of our own format;
  - peer black- and whitelists per listener (§ The relay);
  - `turn_max_allocations`, `turn_max_permissions` and a `shaper` for
    bandwidth.
- **It is Erlang, not C.** TLS goes through `fast_tls`, so OpenSSL; check
  before relying on it that `fast_tls` builds for the Raspberry Pi target
  (aarch64). ejabberd runs there.

Rel (`elixir-webrtc/rel`) is UDP-only and has had no commit since April 2024.
eturnal, the same library as a daemon, and coturn validate the same
credential format: either can stand in where the relay should run outside the
release, with no change to the endpoint or the client.

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

1. **Prove possession.** Proof of possession is its own module,
   `Chat.Pq.ProofOfPossession.verify(user_hash, challenge_id, signature)`,
   owned by neither read sessions nor TURN:
   - it consumes the challenge, fetches `sign_pkey` from a card with
     `deleted_flag: false`, and verifies ML-DSA-87 over the challenge's UTF-8
     bytes;
   - the steps come out of the `with` chain of `ReadGate.open_session/4`,
     which then calls the module as this endpoint does;
   - a deleted identity is `401 unknown_user` on both endpoints, and a
     malformed `user_hash` a `401`, not a `500`;
   - one error mapping for the three PoP failures serves both controllers.
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
behind one address; what bounds a determined abuser is the relay's own quotas
(below).

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
| `TURN_SECRET` | unset → `503`, no relay | The HMAC key of § Credentials, used by the endpoint and the relay's `auth_fun` |
| `TURN_URIS` | unset → `503` | Comma-separated list returned as `uris` |
| `TURN_TTL_SECONDS` | `600` | Credential lifetime. A client renews when less than 150 s remain, so a session never outlives its credential |
| `TURN_RATE_PER_IP_HOUR` | `60` | Issues per client IP per hour |
| `TURN_PUBLIC_IP` | — | `turn_ipv4_address`: the address relays are given out under |
| `TURN_ALLOWED_PEERS` | empty | Comma-separated subnets whitelisted for a LAN deployment (§ The relay) |

The secret lives where `SECRET_KEY_BASE` does: the deploy environment, never
the repository.

---

## The relay

The release starts a `stun` listener per transport when `TURN_SECRET` is
set, with `use_turn`:
- **UDP** on 3478;
- **TLS** on 5349, with the domain's certificate (`certfile`).

**Options:**
- `auth_type: user`, `auth_realm` the domain.
- `auth_fun` reads the expiry from the username:
  - expiry passed → `{expired, Credential}`: the library then accepts only
    the release of an allocation, never a new one;
  - otherwise → the credential, `Base64(HMAC-SHA1(TURN_SECRET, username))`.
- `turn_ipv4_address` is the public address relayed addresses are given out
  under, and `turn_min_port` / `turn_max_port` (49152–65535) bound the relay
  ports.
- **Allocations:** `turn_max_allocations` 4 per credential — each phone
  allocates two per session — and `turn_max_permissions` small.
- **Bandwidth:** a `shaper` of 64 KB/s per connection. A handshake moves
  about 15 KB, a card and an ML-DSA signature each way; the shaper keeps the
  relay from becoming a free tunnel.

### Which peers a relay may reach

A relay that reaches any address is an open proxy into the networks behind
it. The library blocks a peer that is on the blacklist and not on the
whitelist, so the blacklist names everything internal and the whitelist
re-opens what a deployment needs.

**The blacklist, on every deployment:**
- IPv4:
  - `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `127.0.0.0/8`;
  - `169.254.0.0/16`, `172.16.0.0/12`, `192.0.0.0/24`, `192.168.0.0/16`;
  - `198.18.0.0/15`, `240.0.0.0/4`;
- the host's own public address: traffic to it is delivered locally, past the
  firewall;
- IPv6:
  - `::1/128`, `::ffff:0:0/96`, `64:ff9b::/96`;
  - `2001::/32`, `2002::/16`, `fc00::/7`, `fe80::/10`.

**The whitelist depends on where the server is:**
- **On the internet** (`buckitup.xyz`): empty. The relay serves phones on
  the internet and reaches nothing private.
- **On a LAN** (a node in an office or a home): the LAN's own subnets, from
  `TURN_ALLOWED_PEERS` (e.g. `192.168.1.0/24`). Phones on one Wi-Fi with
  client isolation, or on two VLANs of one site, reach each other only
  through it. Loopback and the host itself are never whitelisted.

**Firewall:** UDP 3478, TCP 5349, UDP 49152–65535.

**Certificate:** read by the release, which already serves the domain over
TLS. A renewal reloads it like the endpoint's.

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
- **`ProofOfPossession.verify/3`:** the read-session tests still pass through
  it, and a deleted card is `unknown_user` on both endpoints.
- **The relay's `auth_fun`:** the test vector's credential is accepted before
  its expiry, answered `{expired, …}` after it, and a wrong one refused.
- **Peers:** with `TURN_ALLOWED_PEERS` empty, a permission toward
  `192.168.1.10` is refused; with `192.168.1.0/24` allowed, it is granted, and
  one toward `127.0.0.1` is still refused.
- **End to end:** `chat-frontend/sandbox/handshake-pq2/scripts/check.mjs` with
  `PQ2_TURN_URL`, `PQ2_TURN_USER` and `PQ2_TURN_PASS` set from a response of
  this endpoint completes a confirmed handshake through the relay.

## Acceptance

- Two phones, both on mobile data, with the app pointed at staging: both
  show "Contact confirmed" and the same six digits.
- The same two phones on one Wi-Fi: confirmed over the direct path — the
  selected ICE pair is host to host (`chrome://webrtc-internals`).
- A credential used after its expiry is refused by the relay.
- A relay request toward `127.0.0.1`, the host's private network, the host's
  own public address or `::ffff:127.0.0.1` is refused, and a TCP relay
  request (RFC 6062) is refused outright.
- On a LAN node with `TURN_ALLOWED_PEERS` set to the LAN: two phones on one
  Wi-Fi with client isolation confirm through the relay.
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
- draft-uberti-rtcweb-turn-rest-00 — the credential scheme.

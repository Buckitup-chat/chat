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

1. **Credential endpoint**, in Phoenix: `POST /electric/v1/turn_credentials`,
   authenticated by proof of possession like a read session.
2. **The relay**: coturn, as a system service next to the release.
   - It validates credentials with a secret it shares with Phoenix (the TURN
     REST API scheme, below).
   - It never talks to Phoenix at runtime.

### Why coturn and not an Elixir relay

Rel (`elixir-webrtc/rel`), a TURN server in pure Elixir, would run inside the
release, but today it cannot serve this:

- **UDP only.** Its listener is `:gen_udp` and nothing else. Networks that
  block UDP need TURN over TCP or TLS, and mobile networks are where the relay
  matters.
- **Unmaintained.** Version 0.2.0 dates from 2023, the last commit from April
  2024, and it is described as early-stage.

Rel validates the same credential format. If it gains TCP and TLS, it can
replace coturn with no change to the endpoint or the client.

---

## Credentials

The scheme is *A REST API For Access To TURN Services*
(draft-uberti-rtcweb-turn-rest-00 §2.2). It is what coturn's
`use-auth-secret` and Rel's auth both implement.

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

1. **Prove possession** with the same code as a read session.
   - Extract `Chat.Pq.ReadGate.verify_pop(user_hash, challenge_id,
     signature)` from the `with` chain of `ReadGate.open_session/4`: consume
     the challenge, fetch `sign_pkey` from a card with `deleted_flag: false`,
     verify ML-DSA-87 over the challenge's UTF-8 bytes.
   - Both `open_session/4` and this endpoint call it. A deleted identity is
     `401 unknown_user` here as there, and a malformed `user_hash` is a `401`,
     not a `500`.
   - The error bodies are `ReadSessionController`'s, shared rather than
     copied.
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

**`503 turn_unavailable`** when `TURN_SECRET` is not set: a device on a LAN, or
a Raspberry Pi node with no relay. The client proceeds with its own addresses
only, which is all a shared network needs.

Routing: in the `/electric/v1` scope next to `/challenge`, **outside**
`ElectricReadiness`, with an `options` route for CORS. The endpoint needs the
database, not Electric: a relay must not go dark while Electric starts. A
database it cannot reach is `503 turn_unavailable`, the documented body.

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `TURN_SECRET` | unset → `503` | Shared with coturn's `static-auth-secret` |
| `TURN_URIS` | unset → `503` | Comma-separated list returned as `uris` |
| `TURN_TTL_SECONDS` | `600` | Credential lifetime. A client renews when less than 150 s remain, so a session never outlives its credential |
| `TURN_RATE_PER_IP_HOUR` | `60` | Issues per client IP per hour |

The secret lives where `SECRET_KEY_BASE` does: the deploy environment, never
the repository.

---

## The relay on the staging host

`buckitup.xyz` runs as a release under systemd (`.github/workflows/deploy-staging.yml`).
coturn goes next to it as a package and a service, configured once, outside the
deploy script.

`/etc/turnserver.conf`:

```
listening-port=3478
tls-listening-port=5349
# Clients come over UDP or TLS only (the two URIs), and data channels relay over UDP only.
no-tcp
no-tcp-relay
no-dtls
realm=buckitup.xyz
use-auth-secret
static-auth-secret=<TURN_SECRET>
cert=/etc/coturn/fullchain.pem
pkey=/etc/coturn/privkey.pem
min-port=49152
max-port=65535
fingerprint
no-cli
no-multicast-peers
# Never relay into the host or its networks: a TURN server is otherwise an open proxy to them.
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=240.0.0.0-255.255.255.255
# The host's own public address: traffic to it is delivered locally, past the firewall.
denied-peer-ip=<host public IPv4>
denied-peer-ip=::1
denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
denied-peer-ip=2001::-2001:0:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
# Bytes per second. A handshake moves about 15 KB: a card and an ML-DSA signature each way.
user-quota=4
total-quota=1200
max-bps=64000
bps-capacity=8000000
simple-log
```

- **`external-ip`:** set it when the host is behind NAT.
- **Firewall:** open UDP 3478, TCP 5349, and UDP 49152–65535.
- **Capacity:** each phone allocates two relays per session, so
  `total-quota=1200` serves 600 phones at once, and `user-quota=4` lets one
  credential do no more than two sessions' worth. `max-bps` (64 KB/s per
  session) and `bps-capacity` (8 MB/s in all) keep the relay from becoming a
  free tunnel; a handshake needs a fraction of either.
- **Certificate:** coturn runs as `turnserver` and cannot read certbot's
  root-only `live/` directory. A certbot deploy hook copies `fullchain.pem`
  and `privkey.pem` to `/etc/coturn/` (owner `root`, group `turnserver`, mode
  `0640`) and restarts coturn. Without it TLS is silently off, and networks
  that block UDP get no relay.
- **Logs:** the log names only the random `tag` from the credential, never a
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
- **`ReadGate.verify_pop/3`:** the read-session tests still pass through it,
  and a deleted card is `unknown_user` on both endpoints.
- **End to end:** `chat-frontend/sandbox/handshake-pq2/scripts/check.mjs` with
  `PQ2_TURN_URL`, `PQ2_TURN_USER` and `PQ2_TURN_PASS` set from a response of
  this endpoint completes a confirmed handshake through the relay.

## Acceptance

- Two phones, both on mobile data, with the app pointed at staging: both
  show "Contact confirmed" and the same six digits.
- The same two phones on one Wi-Fi: confirmed over the direct path — the
  selected ICE pair is host to host (`chrome://webrtc-internals`).
- A credential used after its expiry is refused by coturn.
- A relay request toward `127.0.0.1`, the host's private network, the host's
  own public address or `::ffff:127.0.0.1` is refused, and a TCP relay
  request (RFC 6062) is refused outright.
- `turns:buckitup.xyz:5349` completes a TLS allocation after a certificate
  renewal.

---

## Status

Proposed.

## Open questions

1. **TURN over TLS on port 443.** Some networks allow only 443. Sharing it
   with Phoenix takes an ALPN multiplexer in front of both; deferred until a
   network that needs it shows up.
2. **IPv6 relay addresses**, when the host has IPv6. coturn supports them; the
   client's address limit (six per code) may need to grow.
3. **Nodes.** Should a node with internet run a relay for its users? The
   endpoint is ready for it (`TURN_URIS` per deployment); the operations are
   not.

## References

- `chat-frontend/docs/task-handshake-pq2.md` — the handshake that uses the relay.
- [PQ access gating](pq_access_gating.in_progress.md) — why the endpoint is not chain-gated.
- draft-uberti-rtcweb-turn-rest-00 — the credential scheme.

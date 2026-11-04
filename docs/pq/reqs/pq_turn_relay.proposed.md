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

Two parts, both in chat's code, the same on `buckitup.xyz`, on a BuckitUp
device and on a local instance. On a device the platform decides when the
relay's listeners run (§ On a BuckitUp device); the code they run is chat's.

1. **Credential endpoint:** `POST /electric/v1/turn_credentials`,
   authenticated by proof of possession (§ Endpoint).
2. **The relay:** listeners of ProcessOne's `stun` library (hex `stun`) under
   chat's supervision tree. It checks the credentials of § Credentials itself,
   with the secret the endpoint signs them with.
   - Every allocation holds a UDP port and a process in chat's BEAM. The
     relay port range caps them, so chat's file-descriptor limit is set above
     its own needs plus the range.

### Why the `stun` library, and what it needs around it

- **It covers the transports:** UDP and TCP listeners (and TLS, unused
  here — § The relay). Networks that block UDP need TCP.
- **It is maintained:** 1.2.23 is from August 2026. ProcessOne ships it in
  ejabberd and builds eturnal, a standalone TURN server, on it.
- **It has the hooks this needs:**
  - `auth_fun`, for credentials of our own format;
  - peer black- and whitelists per listener;
  - `turn_max_allocations` and `turn_max_permissions`.
- **It is Erlang, not C,** but it depends on `fast_tls`, an OpenSSL NIF, even
  with no TLS listener: check that it builds for the Raspberry Pi target
  (aarch64) before relying on it. ejabberd runs there.

Rel (`elixir-webrtc/rel`) is UDP-only and has had no commit since April 2024.

**What the library does not do, read from its source (`stun.erl`,
`turn.erl`), and what covers each:**

| The library | What covers it |
|---|---|
| Checks a request's peer addresses as a set: one whitelisted address lets every blacklisted one in the same request through | No deployment sets a whitelist. Allowed ranges are cut out of the blacklist instead, and with an empty whitelist the check is per address (§ Which peers a relay may reach) |
| Takes peer lists only as `turn_blacklist_peers` / `turn_whitelist_peers`; any other key exits the listener with `unknown_option` | `Chat.Turn.Listener` builds every listener's options in one place |
| Matches an IPv4 peer against a `::ffff:0:0/96` entry as if it were mapped, so that entry blocks every IPv4 peer | The entry is never listed. The relay allocates IPv4 only, and an IPv6 peer, mapped or not, fails its family check |
| `{expired, Pass}` from `auth_fun` only stops a new Allocate; Refresh, CreatePermission and ChannelBind still pass | `auth_fun` refuses an expired credential outright. An allocation then ends within the lifetime last granted to it |
| The `shaper` limits only TCP clients, never UDP or relayed traffic | Per-source rate limits in the host firewall (nftables) on 3478 and the relay port range |
| No global cap on allocations | The relay port range is the cap, with the endpoint's per-address issue limit in front of it |

---

## Credentials

The scheme is *A REST API For Access To TURN Services*
(draft-uberti-rtcweb-turn-rest-00 §2.2): the relay's `auth_fun` checks it.
`TURN_SECRET` is 32 random bytes chat generates at start and keeps in memory:
the endpoint and the relay are one release, so there is nothing to configure,
and a restart drops the allocations and the credentials together.

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

1. **Prove possession.** `ReadGate.verify_user(user_hash, challenge_id,
   signature_b64)` — extracted from the `with` chain of
   `ReadGate.open_session/4` — consumes the challenge, fetches the
   `sign_pkey` of a card with `deleted_flag: false`, and verifies ML-DSA-87
   over the challenge's UTF-8 bytes. This endpoint and `open_session` both
   call it; `open_session` then checks the vouch chain on top.
   - A deleted identity is `401 unknown_user` on both endpoints, and a
     malformed `user_hash` a `401`, not a `500`; one error mapping for the
     three failures serves both controllers.
   - Ingest is not involved: `ChatWeb.Utils.IngestPop` stays as it is — it
     returns the raw challenge and signature for each shape's validation to
     verify against the mutation's own key, which differs per shape.
2. **Issue** the credentials above. `uris` is `TURN_URIS` verbatim, e.g.:

   ```json
   ["turn:buckitup.xyz:3478?transport=udp",
    "turn:buckitup.xyz:3478?transport=tcp"]
   ```

   **Two URIs, not more.** The browser allocates a relay on every URI it is
   given, a phone's code carries at most two relay addresses, and a slow or
   blocked transport holds up address gathering. UDP is the fast path; TCP
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

**`503 turn_unavailable`** when the relay is not running: a server whose
`DOMAIN` does not resolve to an IPv4 address (and has no `TURN_PUBLIC_IP`
override) runs none. The client proceeds with its own addresses only, which is
all a shared network without client isolation needs.

Routing: in the `/electric/v1` scope next to `/challenge`, **outside**
`ElectricReadiness`, with an `options` route for CORS. The endpoint needs the
database, not Electric: a relay must not go dark while Electric starts. A
database it cannot reach is `503 turn_unavailable`, the documented body.

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `TURN_PUBLIC_IP` | resolved from `DOMAIN` at startup; unresolvable → no relay, `503` | `turn_ipv4_address`: the IPv4 address the stun library hands out in relay allocations. Override when the relay's IP differs from the domain's A record |
| `TURN_URIS` | `turn:<DOMAIN>:3478?transport=udp`, `turn:<DOMAIN>:3478?transport=tcp` | Comma-separated list returned as `uris`. Uses the hostname so clients resolve it themselves |
| `TURN_TTL_SECONDS` | `600` | Credential lifetime. A client renews when less than 150 s remain, so a session never outlives its credential |
| `TURN_RATE_PER_IP_HOUR` | `60` | Issues per client IP per hour |

`DOMAIN` is already set in `config/prod.exs` and `config/platform/target.exs`.
When neither `TURN_PUBLIC_IP` nor `DOMAIN` yields an IPv4 address, `enabled?/0`
returns `false` and the endpoint answers `503`. A device sets none of these
(§ On a BuckitUp device).

---

## The relay

On the server, two `stun` listeners with `use_turn`, both on 3478:
- **UDP**;
- **TCP**, for networks that block UDP.

**No TLS.** It would add nothing the channel needs: DTLS runs end to end
between the phones, and the credential is an HMAC the relay checks, never sent
in clear. It would cost a certificate the relay can read — on `buckitup.xyz`
the reverse proxy holds Let's Encrypt's, and a device has a year-long one of
its own. What TLS alone would reach is a network that lets only TLS on 443
through (Open question 1).

**`auth_fun(User, Realm)`** answers the credential or `<<"">>`, and never
raises — it runs inside the listener for every client:
- `<<"">>` when the realm is not ours, the username does not parse as
  `<expiry>:<tag>`, or the expiry has passed;
- otherwise `Base64(HMAC-SHA1(TURN_SECRET, username))`.

**Options:**
- `auth_type: user`, `auth_realm` the domain.
- `turn_ipv4_address`: `TURN_PUBLIC_IP` if set, otherwise `DOMAIN` resolved
  via `:inet.getaddr(domain, :inet)` at startup; on a device, each listener's
  own address. The library's default is `127.0.0.1`, which would hand out
  relay addresses nobody can reach, so the relay refuses to start a listener
  without it.
- `turn_min_port` / `turn_max_port`: the relay port range, which is also the
  cap on concurrent allocations.
- `turn_max_allocations` 4 per credential: each phone allocates two per
  session.
- `turn_max_permissions` 16. The library counts existing and requested
  addresses together, repeats included, and a peer's code carries up to six;
  a tight limit breaks a permission refresh.

**The host firewall** rate-limits each source on 3478 and the relay port
range — the bandwidth the library does not shape. A handshake moves about
15 KB, a card and an ML-DSA signature each way.

### Which peers a relay may reach

A relay that reaches any address is an open proxy into the networks behind it.
The library refuses a peer that is on the blacklist and not on the whitelist,
but checks all peers of one request as a set (§ Why the `stun` library). So
the whitelist stays empty everywhere, and the ranges a relay may reach are
**holes cut out of the blacklist**: `turn_blacklist_peers` = (base blacklist ∪
the host's own addresses) − allowed ranges, written as CIDR blocks
(`Chat.Turn.PeerPolicy`, `Chat.Turn.Cidr`). The platform's own networks are
gray — inside the blacklisted RFC 1918 ranges — and are reachable only through
such holes. A hole never covers loopback, `0.0.0.0/8` or the host's own
addresses: they are subtracted from the allowed ranges first.

**The blacklist, on every deployment:**
- IPv4:
  - `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `127.0.0.0/8`;
  - `169.254.0.0/16`, `172.16.0.0/12`, `192.0.0.0/24`, `192.168.0.0/16`;
  - `198.18.0.0/15`, `240.0.0.0/4`;
- the host's own public address: traffic to it is delivered locally, past the
  firewall.

No IPv6 entries: the relay is IPv4-only, and an IPv6 peer fails the family
check first. No `::ffff:0:0/96` entry in any case (§ Why the `stun` library).

**The allowed ranges depend on where the server is:**
- **On the internet** (`buckitup.xyz`): none. The relay serves phones on the
  internet and reaches nothing private.
- **On a BuckitUp device** (a node in an office or a home): the device's gray
  IPs, minus its own addresses. They come from VintageNet's live
  configuration of each interface (defaults in the platform repo's
  `config/platform/target.exs`):

  | Interface | Network | Device | Allowed |
  |---|---|---|---|
  | `wlan0` | the device's access point `BuckitUp.app`, `192.168.25.0/24` | `.1` | the DHCP pool `.10`–`.250` |
  | `eth0`, profile `no_internet` | the device serves the wired LAN, `192.168.24.0/24` | `.1` | the DHCP pool `.10`–`.250` |
  | `eth0`, profile `internet` | a DHCP client of the site's LAN | its lease | the network of the lease (address and prefix length from VintageNet), minus the lease |
  | `usb0` | a host on USB, `192.168.26.0/24` | `.1` | the DHCP pool `.10`–`.250` |

  Each pool is written as the CIDR blocks that cover it. Phones on the
  device's Wi-Fi and phones on the wired side then reach each other through
  the relay, as do phones on a site Wi-Fi with client isolation.
  - The relay keeps no list of its own: the platform derives it from
    VintageNet (§ On a BuckitUp device). Its clients can reach these networks
    anyway; what a hole must never open is loopback and the device itself.
  - No library patch is needed: with an empty whitelist, a request naming a
    LAN address and `127.0.0.1` is refused for `127.0.0.1`.

**Firewall** on the server: open UDP and TCP 3478 and the relay port range.
The reverse proxy is not in the path: TURN goes to chat's listeners directly.

**Logs:** the log names only the random `tag` from the credential, never a
`user_hash`.

### On a BuckitUp device

The same relay code, with what differs on a LAN. Chat and the platform run
in one BEAM, so the platform calls chat's modules directly — no bridge
messages:

- **Who runs it:** chat's `Chat.Turn.Supervisor` starts on a host only.
  On a device `Platform.Network.TurnRelay` (target only) subscribes to
  VintageNet `addresses` and `config` of `wlan0`, `eth0` and `usb0`, plans
  each interface's address and allowed ranges (`TurnRelay.Plan`), and calls
  `Chat.Turn.LanRelay.start/3` and `stop/1`. A listener starts as soon as its
  interface has an IPv4 address; a start that fails (the address still
  settling) is retried after 5 s. `Chat.Turn.Config.setup/0` runs in chat as
  everywhere, so the platform's listeners check credentials with the same
  secret and realm the endpoint signs with.

- **Listeners:** one UDP listener on 3478 per LAN interface — `wlan0`,
  `eth0`, `usb0`, never ZeroTier — bound to the device's address there, with
  that address as its `turn_ipv4_address`. A phone gets a relay address on
  the network it reached the device on. No TCP listener: a LAN does not block
  UDP.
- **`uris`:** the endpoint answers one URI, the relay on the address the
  request arrived at (the socket's local address) —
  `turn:192.168.25.1:3478?transport=udp` for a phone on the device's Wi-Fi.
  The phone reached chat there, so it reaches the relay there. A request that
  arrived at an address with no relay (ZeroTier, loopback) gets `503`.
- **Config:** `Chat.Turn.Config` is in `:lan` mode on a device (chosen by the
  compile target): it ignores `TURN_*` and does not resolve `DOMAIN`, which a
  device maps to `127.0.0.1`.
- **Allowed ranges** (§ Which peers a relay may reach): when `eth0`'s profile
  or lease changes, VintageNet reports a new address or config and only the
  `eth0` listener restarts, with the new address and ranges. Restarting it
  drops its live allocations.
- **Firewall:** nothing to open. The platform adds no input policy, so input
  is accepted on every interface.
- The endpoint's per-address rate limit holds as on the server.

---

## Tests

- **Credential function:** the test vector above. The username carries a
  future expiry and a 32-hex tag, and two issues never share a tag.
- **Controller:** each error row of § Endpoint. A valid PoP returns the
  configured `uris`. With neither `TURN_PUBLIC_IP` set nor `DOMAIN` resolvable
  the answer is `503`, and in `trust` mode an identity with no vouch still
  gets credentials.
- **Rate limit:** the 61st issue from one IP in an hour is `429` with
  `retry_after`; another IP is unaffected; an expired entry is swept.
- **`verify_user`:** a deleted card is `unknown_user` on both the TURN and
  read-session endpoints; `ReadGate.open_session` tests pass unchanged.
- **The relay's `auth_fun`:** the test vector's credential is accepted before
  its expiry and refused after it; a wrong credential, a wrong realm and a
  username that does not parse are refused, and none raises.
- **Peers:**
  - on the server, a permission toward a public IPv4 peer is granted and one
    toward `192.168.1.10` refused;
  - with a device's allowed ranges, `192.168.25.20` and `192.168.24.20` are
    granted; `127.0.0.1`, `192.168.25.1` and `192.168.24.1` are refused, and
    the whitelist is empty, so they are refused also in a request that names
    `192.168.25.20`;
  - the ranges built for `eth0` on profile `internet` with lease
    `10.1.2.3/16` covers `10.1.0.0/16` and leaves out `10.1.2.3`, and after a
    switch to `no_internet` the `10.1.0.0/16` range is refused.
- **On a device:**
  - the plan from VintageNet state gives one listener per interface, each
    with its own address as `turn_ipv4_address`; another `eth0` lease
    restarts only that listener, with the new address and ranges;
  - with no `TURN_*` variable set the endpoint issues credentials, and a
    request that arrived at `192.168.25.1` gets
    `turn:192.168.25.1:3478?transport=udp` as its only URI.
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
- On a BuckitUp device, with no relay configuration on it: a phone on its
  Wi-Fi `BuckitUp.app` and a phone on its wired side confirm through the
  relay, in both `eth0` profiles.
- From a network that blocks UDP, `turn:buckitup.xyz:3478?transport=tcp`
  completes an allocation and the handshake confirms.

---

## Status

Proposed.

## Open questions

1. **TURN over TLS on port 443.** Some networks let only TLS on 443 through.
   It takes a certificate the relay can read and an ALPN multiplexer sharing
   443 with the reverse proxy; deferred until a network that needs it shows
   up.
2. **IPv6 relay addresses**, when the host has IPv6: whether to relay over
   IPv6 at all, and the client's limit of two IPv6 addresses per code.
3. **Nodes on the internet.** Whether a node with a public address runs a
   relay for its users; its configuration is `buckitup.xyz`'s.

## References

- `chat-frontend/docs/task-handshake-pq2.md` — the handshake that uses the relay.
- [PQ access gating](pq_access_gating.in_progress.md) — why the endpoint is not chain-gated.
- [Proof-of-Possession](../invariants/01_proof_of_possession.md) — the ingest PoP; `ReadGate.verify_user` shares the pattern.
- `Buckitup-chat/platform`: `config/platform/target.exs` (the device networks), `Platform.Network.TurnRelay` (runs a device's listeners from VintageNet) — where a device relay's addresses and allowed ranges come from.
- draft-uberti-rtcweb-turn-rest-00 — the credential scheme.

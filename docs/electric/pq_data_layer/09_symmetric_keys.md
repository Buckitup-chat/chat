# Symmetric Key Derivation

> Status: **open** — current dialogs use raw SHA3-512; migration to HKDF planned.

## Problem

The PQ data layer encrypts content with AES-256-GCM under keys derived from the author's private material. The current derivation in [pq_dialogs.md](../../reqs/pq_dialogs.md) is a single SHA3-512 hash:

```
sender_msg_key = SHA3-512(
    "buckitup/dialog-mk/v1"
 || sign_skey
 || kem_skey
 || contact_skey
 || peer_user_hash
)
```

This produces a 512-bit value that is reused directly as:

1. AES-256-GCM key for **message content** (`content_b64`)
2. AES-256-GCM key for **causal references** (`refs_map_b64`)
3. AES-256-GCM key for **reaction type** (`type_b64`)
4. HMAC-SHA3-512 key for **reaction hash** (`reaction_hash`)

Three issues:

| Issue | Risk |
|---|---|
| **No key separation** — one value serves four cryptographic roles (three AES-GCM encryptions + one HMAC). Compromise of one usage leaks material for all others. Cross-protocol attacks between AES-GCM and HMAC-SHA3-512 are not known today, but the security argument cannot treat them independently. | Moderate — violates key-separation principle |
| **Output size ambiguity** — SHA3-512 produces 64 bytes; AES-256-GCM expects exactly 32. The spec does not state how the 512-bit output maps to a 256-bit key (truncation? first half?). | Low — but underspecified |
| **No extensibility** — adding a new key usage (e.g., attachment encryption, room subkeys) requires inventing a new ad-hoc derivation rather than adding a label. | Design friction |

The same gap exists in the KEM wrap step (acknowledged as problem #13 in `pq_dialogs.md`): `ML-KEM-1024`'s shared secret is used directly as the AES-256-GCM `wrap_key` without KDF separation.

## Approach

**Replace raw SHA3-512 with HKDF (RFC 5869) using HMAC-SHA-256 as the underlying PRF.** HKDF is a two-phase extract-then-expand construction that produces independent, fixed-length subkeys from a single source of keying material.

### Why HKDF

- **Formal security reduction** — HKDF has a proof in the standard model (Krawczyk, 2010). Ad-hoc `SHA3(secrets)` does not.
- **Key separation by label** — each `info` string produces a cryptographically independent subkey. Adding a new usage is one new label, not a new derivation.
- **Explicit output length** — `L=32` means exactly 256 bits. No ambiguous truncation.
- **Widely available** — two HMAC calls. OTP 28's `crypto:mac(:hmac, :sha256, ...)` and WebCrypto's `SubtleCrypto.deriveBits("HKDF", ...)` both support it natively; no external dependency on either side.

### Why SHA-256 (not SHA3-256)

The rest of the PQ data layer uses SHA3-512 for identity hashes (`user_hash`, `dialog_hash`, `sign_hash`). HKDF's HMAC is a different role — a PRF for key derivation, not a collision-resistant hash for identifiers — so the hash family can differ. SHA-256 is chosen because:

- **WebCrypto compatibility** — the frontend encrypts User storage items using the same KDF. WebCrypto's `SubtleCrypto.deriveBits("HKDF", ...)` supports SHA-256, SHA-384, and SHA-512 but **not** SHA3 variants. Using SHA-256 means identical native HKDF on both backend (OTP `crypto`) and frontend (WebCrypto) with zero custom crypto code in the browser.
- **Equivalent security inside HMAC** — SHA-256's Merkle-Damgård length extension weakness does not apply inside HMAC, which is a double-hashing construction. HKDF's security proof (Krawczyk, 2010) requires HMAC to be a PRF; both SHA-256 and SHA3-256 satisfy this equally. NIST approves both for all cryptographic applications including key derivation (SP 800-56C Rev. 2).
- **HKDF-Expand output blocks match AES-256 key length** (32 bytes) — one block per subkey, no truncation.
- **256-bit PRF security** is sufficient for 256-bit key derivation.
- **Performance** — SHA-256 benefits from hardware acceleration (SHA-NI instructions) on most modern CPUs.

SHA3-512 remains the correct choice for identity hashes, where 256-bit collision resistance (from 512-bit output) matters and WebCrypto is not involved.

### Construction

#### Phase 1 — Extract

Concentrate the multi-source input keying material (IKM) into a fixed-length pseudorandom key (PRK):

```
IKM  = sign_skey || kem_skey || contact_skey || peer_user_hash
salt = "buckitup/dialog-mk/v1"

PRK  = HMAC-SHA-256(key = salt, data = IKM)              # 32 bytes
```

The salt provides domain separation (same role as the old prefix tag). Per RFC 5869 §3.1, when salt is a non-secret constant the extract step still produces a uniformly distributed PRK from high-entropy IKM.

#### Phase 2 — Expand

Derive independent subkeys from PRK using distinct `info` labels:

```
content_key    = HKDF-Expand(PRK, info = "content",    L = 32)
refs_key       = HKDF-Expand(PRK, info = "refs",       L = 32)
reaction_key   = HKDF-Expand(PRK, info = "reaction",   L = 32)
reaction_mac   = HKDF-Expand(PRK, info = "react-mac",  L = 32)
```

Where `HKDF-Expand` for a single 32-byte block is:

```
HKDF-Expand(PRK, info, 32) = HMAC-SHA-256(key = PRK, data = info || 0x01)
```

Each subkey is cryptographically independent — compromising `reaction_mac` reveals nothing about `content_key`.

#### Wrap key (KEM step)

The same pattern applies to the KEM wrap in `dialog_keys`. Currently:

```
(peer_kem_wrap_key, wrap_key) = ML-KEM-1024.Encap(peer.crypt_pkey)
peer_wrapped_msg_key          = AES-256-GCM.encrypt(wrap_key, sender_msg_key)
```

With HKDF:

```
(peer_kem_wrap_key, shared_secret) = ML-KEM-1024.Encap(peer.crypt_pkey)
wrap_key                           = HKDF(IKM = shared_secret,
                                          salt = "buckitup/dialog-wrap/v1",
                                          info = "wrap",
                                          L = 32)
peer_wrapped_msg_key               = AES-256-GCM.encrypt(wrap_key, sender_msg_key)
```

This resolves problem #13 from `pq_dialogs.md` (no KDF separation in the wrap step).

### Affected tables

| Table | Field | Current key | HKDF subkey |
|---|---|---|---|
| `dialog_messages` | `content_b64` | `sender_msg_key` | `content_key` |
| `dialog_messages` | `refs_map_b64` | `sender_msg_key` | `refs_key` |
| `dialog_messages_versions` | `content_b64` | `sender_msg_key` | `content_key` |
| `dialog_messages_versions` | `refs_map_b64` | `sender_msg_key` | `refs_key` |
| `dialog_message_reactions` | `type_b64` | `sender_msg_key` | `reaction_key` |
| `dialog_message_reactions` | `reaction_hash` | `sender_msg_key` (HMAC key) | `reaction_mac` |
| `dialog_keys` | `peer_wrapped_msg_key_b64` | KEM shared secret (direct) | `wrap_key` (via HKDF) |

### Label registry

Labels are constant ASCII strings. New usages MUST be registered here before use.

| Label | Purpose | Introduced |
|---|---|---|
| `"content"` | AES-256-GCM key for message/version `content_b64` | v1 |
| `"refs"` | AES-256-GCM key for `refs_map_b64` | v1 |
| `"reaction"` | AES-256-GCM key for reaction `type_b64` | v1 |
| `"react-mac"` | HMAC-SHA3-512 key for `reaction_hash` | v1 |
| `"wrap"` | AES-256-GCM key for KEM wrap step (salt differs) | v1 |

### Reference implementation

OTP 28 does not export a dedicated HKDF function. The construction uses `crypto:mac/4`:

```elixir
defmodule Chat.Crypto.Hkdf do
  @hash :sha256
  @hash_len 32

  def extract(ikm, salt) do
    :crypto.mac(:hmac, @hash, salt, ikm)
  end

  def expand(prk, info, length \\ @hash_len) do
    1..ceil(length / @hash_len)
    |> Enum.reduce({<<>>, <<>>}, fn i, {acc, prev} ->
      t = :crypto.mac(:hmac, @hash, prk, prev <> info <> <<i::8>>)
      {acc <> t, t}
    end)
    |> elem(0)
    |> binary_part(0, length)
  end

  def derive(ikm, salt, info, length \\ @hash_len) do
    ikm |> extract(salt) |> expand(info, length)
  end
end
```

## Where this applies

- **Dialog key derivation**: [pq_dialogs.md §Key derivation](../../reqs/pq_dialogs.md) — replaces raw SHA3-512
- **Dialog key wrapping**: [pq_dialogs.md §Key wrapping](../../reqs/pq_dialogs.md) — resolves problem #13
- **User storage encryption** (frontend) — same HKDF-SHA-256 via WebCrypto `SubtleCrypto.deriveBits`
- **Future room keys**: same HKDF pattern with a different salt (e.g., `"buckitup/room-mk/v1"`)

## Invariants

- Every AES-256-GCM key MUST be derived via HKDF-Expand with a unique `info` label. Direct use of hash output or KEM shared secret as an encryption key is prohibited.
- `info` labels are ASCII, unique per usage, and registered in the label registry above. Reusing a label for a different purpose breaks key separation.
- HKDF-Extract salt is a non-secret domain-separation constant. Different key families (dialog, room, wrap) use different salts.
- Output length is always 32 bytes (256 bits) for AES-256-GCM keys. No truncation of longer outputs; no zero-padding of shorter ones.
- The underlying PRF is HMAC-SHA-256. Changing the hash function changes all derived keys — this constitutes a key version bump (new salt tag).
- Identity hashes (`user_hash`, `dialog_hash`, `sign_hash`) remain SHA3-512. Different role (collision-resistant identifiers), different hash.

## Post-quantum note

AES-256-GCM is considered quantum-resistant. Grover's algorithm halves the effective key strength, reducing AES-256 from 256-bit to 128-bit security — still well beyond feasible brute force. The same applies to HMAC-SHA-256 as a PRF inside HKDF. The post-quantum threat targets asymmetric primitives (RSA, ECC, ECDH), which is why the data layer uses ML-KEM-1024 for key exchange. The symmetric side (AES-256-GCM + HKDF-SHA-256) requires no post-quantum migration.

## References

- [RFC 5869 — HKDF](https://datatracker.ietf.org/doc/html/rfc5869)
- [Krawczyk, 2010 — Cryptographic Extraction and Key Derivation: The HKDF Scheme](https://eprint.iacr.org/2010/264.pdf)
- [Dodis et al., 2018 — Backdoored Hash Functions: Immunizing HMAC and HKDF](https://eprint.iacr.org/2018/362.pdf)
- [Bhattacharyya & Nandi, 2023 — When Messages are Keys: Is HMAC a dual-PRF?](https://eprint.iacr.org/2023/861.pdf)
- [NIST SP 800-56C Rev. 2 — Key-Derivation Methods in Key-Establishment Schemes](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-56Cr2.pdf)
- [NIST Policy on Hash Functions](https://csrc.nist.gov/Projects/Hash-Functions/NIST-Policy-on-Hash-Functions)

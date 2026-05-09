# Symmetric Key Derivation

> Status: **solved** — `pq_dialogs.md` specifies HKDF-SHA3-256 for all symmetric key derivation.

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

Two issues:

| Issue | Risk |
|---|---|
| **Output size ambiguity** — SHA3-512 produces 64 bytes; AES-256-GCM expects exactly 32. The spec does not state how the 512-bit output maps to a 256-bit key (truncation? first half?). | Low — but underspecified |
| **No formal KDF** — a raw hash is not a key derivation function. HKDF has a security proof; ad-hoc `SHA3(secrets)` does not. | Moderate — no provable security reduction |

The same gap exists in the KEM wrap step (acknowledged as problem #13 in `pq_dialogs.md`): `ML-KEM-1024`'s shared secret is used directly as the AES-256-GCM `wrap_key` without KDF separation.

## Approach

**Replace raw SHA3-512 with HKDF (RFC 5869) using HMAC-SHA3-256 as the underlying PRF.** HKDF is a two-phase extract-then-expand construction that produces a properly derived, fixed-length key from a source of keying material.

The output is a single 256-bit `sender_msg_key` used for all encryption and MAC operations within that dialog direction — same usage model as today, but with a provably secure derivation.

### Why HKDF

- **Formal security reduction** — HKDF has a proof in the standard model (Krawczyk, 2010). Ad-hoc `SHA3(secrets)` does not.
- **Explicit output length** — `L=32` means exactly 256 bits. No ambiguous truncation.
- **Extensible** — if future work requires subkeys (rooms, attachments), additional `info` labels can derive independent keys from the same PRK without redesigning the derivation.

### Why SHA3-256

The rest of the PQ data layer uses SHA3-512 for identity hashes (`user_hash`, `dialog_hash`, `sign_hash`). HKDF's HMAC is a different role — a PRF for key derivation, not a collision-resistant hash for identifiers — but using the same hash family keeps the cryptographic surface area uniform.

- **SHA3 family consistency** — the entire PQ data layer uses SHA3. No second hash family to audit, implement, or explain.
- **No length-extension weakness** — SHA3 (Keccak sponge) is immune to length-extension attacks by construction. While HMAC neutralizes this for Merkle-Damgård hashes (SHA-256), SHA3 does not require that mitigation in the first place.
- **HKDF-Expand output blocks match AES-256 key length** — SHA3-256 produces 32 bytes, so one HMAC block yields one AES-256 key with no truncation.
- **256-bit PRF security** is sufficient for 256-bit key derivation.
- **OTP 28 support** — `crypto:mac(:hmac, :sha3_256, ...)` works natively.
- **Frontend support** — WebCrypto does not support SHA3 variants in `SubtleCrypto.deriveBits("HKDF", ...)`, so the frontend implements HKDF-SHA3-256 directly (two HMAC-SHA3-256 calls). SHA3-256 is available via `SubtleCrypto.digest("SHA3-256", ...)` in modern browsers; HMAC-SHA3-256 uses `SubtleCrypto.sign("HMAC", ...)` with an imported SHA3-256 key. No external dependencies.

SHA3-512 remains the correct choice for identity hashes, where 256-bit collision resistance (from 512-bit output) matters.

### Construction

#### Phase 1 — Extract

Concentrate the multi-source input keying material (IKM) into a fixed-length pseudorandom key (PRK):

```
IKM  = sign_skey || kem_skey || contact_skey || peer_user_hash
salt = "buckitup/dialog-mk/v1"

PRK  = HMAC-SHA3-256(key = salt, data = IKM)              # 32 bytes
```

The salt provides domain separation (same role as the old prefix tag). Per RFC 5869 §3.1, when salt is a non-secret constant the extract step still produces a uniformly distributed PRK from high-entropy IKM.

#### Phase 2 — Expand

Derive a single `sender_msg_key` from PRK:

```
sender_msg_key = HKDF-Expand(PRK, info = "dialog-mk", L = 32)
```

Where `HKDF-Expand` for a single 32-byte block is:

```
HKDF-Expand(PRK, info, 32) = HMAC-SHA3-256(key = PRK, data = info || 0x01)
```

The resulting 256-bit key is used directly as:

1. AES-256-GCM key for **message content** (`content_b64`)
2. AES-256-GCM key for **causal references** (`refs_map_b64`)
3. AES-256-GCM key for **reaction type** (`type_b64`)
4. HMAC-SHA3-512 key for **reaction hash** (`reaction_hash`)

Each usage has its own per-operation fresh random nonce (AES-GCM) or unique input domain (HMAC over `message_id || reactor_hash || type_plaintext`), so the single key is safe across these roles. Cross-protocol attacks between AES-GCM and HMAC-SHA3-512 under the same key are not known, and the distinct nonce/input structures prevent key-stream or MAC collisions.

#### Wrap key (KEM step)

The same HKDF pattern applies to the KEM wrap in `dialog_keys`. Currently:

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

| Table | Field | Key | Encrypt / MAC |
|---|---|---|---|
| `dialog_messages` | `content_b64` | `sender_msg_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |
| `dialog_messages` | `refs_map_b64` | `sender_msg_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |
| `dialog_messages_versions` | `content_b64` | `sender_msg_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |
| `dialog_messages_versions` | `refs_map_b64` | `sender_msg_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |
| `dialog_message_reactions` | `type_b64` | `sender_msg_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |
| `dialog_message_reactions` | `reaction_hash` | `sender_msg_key` via `hkdf_derive/3` | `hmac_sha3_512/2` |
| `dialog_keys` | `peer_wrapped_msg_key_b64` | `wrap_key` via `hkdf_derive/3` | `aes_gcm_encrypt/2` |

All functions are in `EnigmaPq` (`lib/enigma_pq/enigma_pq.ex`).

### Implementation

Implemented in `EnigmaPq` (`lib/enigma_pq/enigma_pq.ex`):

| Function | Role |
|---|---|
| `EnigmaPq.hkdf_extract/2` | HKDF Extract — `HMAC-SHA3-256(key = salt, data = ikm)` |
| `EnigmaPq.hkdf_expand/2,3` | HKDF Expand — iterative `HMAC-SHA3-256` with counter byte |
| `EnigmaPq.hkdf_derive/3,4` | Extract-then-expand convenience |
| `EnigmaPq.hmac_sha3_256/2` | Underlying PRF |
| `EnigmaPq.hmac_sha3_512/2` | Keyed MAC for `reaction_hash` |
| `EnigmaPq.aes_gcm_encrypt/2` | AES-256-GCM producing `nonce \|\| ciphertext \|\| tag` |
| `EnigmaPq.aes_gcm_decrypt/2` | AES-256-GCM decryption, returns plaintext or `:error` |

OTP 28 does not export a dedicated HKDF function. The construction uses `crypto:mac/4`:

```elixir
# EnigmaPq.hkdf_extract/2
def hkdf_extract(ikm, salt) do
  :crypto.mac(:hmac, :sha3_256, salt, ikm)
end

# EnigmaPq.hkdf_expand/2,3
def hkdf_expand(prk, info, length \\ 32) do
  1..ceil(length / 32)
  |> Enum.reduce({<<>>, <<>>}, fn i, {acc, prev} ->
    t = :crypto.mac(:hmac, :sha3_256, prk, prev <> info <> <<i::8>>)
    {acc <> t, t}
  end)
  |> elem(0)
  |> binary_part(0, length)
end

# EnigmaPq.hkdf_derive/3,4
def hkdf_derive(ikm, salt, info, length \\ 32) do
  ikm |> hkdf_extract(salt) |> hkdf_expand(info, length)
end
```

## Where this applies

- **Dialog key derivation**: [pq_dialogs.md §Key derivation](../../reqs/pq_dialogs.md) — replaces raw SHA3-512 with HKDF-SHA3-256, same single-key-per-side model
- **Dialog key wrapping**: [pq_dialogs.md §Key wrapping](../../reqs/pq_dialogs.md) — resolves problem #13
- **User storage encryption** (frontend) — same HKDF-SHA3-256 (implemented via HMAC-SHA3-256 over WebCrypto)
- **Future room keys**: same HKDF pattern with a different salt (e.g., `"buckitup/room-mk/v1"`)

## Invariants

- `sender_msg_key` MUST be derived via HKDF-SHA3-256 (extract-then-expand). Direct use of a raw hash output as an encryption key is prohibited.
- The KEM shared secret from `ML-KEM-1024.Encap` MUST be passed through HKDF before use as a `wrap_key`. Direct use of KEM output as an encryption key is prohibited.
- HKDF-Extract salt is a non-secret domain-separation constant. Different key families (dialog, room, wrap) use different salts.
- Output length is always 32 bytes (256 bits). No truncation of longer outputs; no zero-padding of shorter ones.
- The underlying PRF is HMAC-SHA3-256. Changing the hash function changes all derived keys — this constitutes a key version bump (new salt tag).
- Identity hashes (`user_hash`, `dialog_hash`, `sign_hash`) remain SHA3-512. Different role (collision-resistant identifiers), different hash.

## Post-quantum note

AES-256-GCM is considered quantum-resistant. Grover's algorithm halves the effective key strength, reducing AES-256 from 256-bit to 128-bit security — still well beyond feasible brute force. The same applies to HMAC-SHA3-256 as a PRF inside HKDF. The post-quantum threat targets asymmetric primitives (RSA, ECC, ECDH), which is why the data layer uses ML-KEM-1024 for key exchange. The symmetric side (AES-256-GCM + HKDF-SHA3-256) requires no post-quantum migration.

## References

- [RFC 5869 — HKDF](https://datatracker.ietf.org/doc/html/rfc5869)
- [Krawczyk, 2010 — Cryptographic Extraction and Key Derivation: The HKDF Scheme](https://eprint.iacr.org/2010/264.pdf)
- [Dodis et al., 2018 — Backdoored Hash Functions: Immunizing HMAC and HKDF](https://eprint.iacr.org/2018/362.pdf)
- [NIST SP 800-56C Rev. 2 — Key-Derivation Methods in Key-Establishment Schemes](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-56Cr2.pdf)
- [NIST Policy on Hash Functions](https://csrc.nist.gov/Projects/Hash-Functions/NIST-Policy-on-Hash-Functions)

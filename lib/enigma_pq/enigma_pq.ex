defmodule EnigmaPq do
  @moduledoc """
  Encryption primitives using OTP 28 functions for Post-Quantum Cryptography.
  Uses ML-DSA-87 for signing, ML-KEM-1024 for key encapsulation,
  AES-256-GCM for symmetric encryption, and HKDF-SHA3-256 for key derivation.

  ## Spec references

    - `docs/reqs/pq_user.md` — user identity, key generation, certificates
    - `docs/reqs/pq_dialogs.md` — dialog key derivation, wrapping, message encryption
    - `docs/electric/pq_data_layer/09_symmetric_keys.md` — HKDF construction and rationale
    - `docs/electric/pq_data_layer/07_content_polymorphism.md` — content blob format
  """

  @aes_gcm_nonce_size 12
  @aes_gcm_tag_size 16
  @hkdf_hash :sha3_256
  @hkdf_hash_len 32

  # --- Hashing ---
  # Spec: pq_user.md §Algorithms — SHA3-512 for user_hash, crypt_cert, contact_cert
  # Spec: pq_dialogs.md §Identifiers — SHA3-512 for dialog_hash, sign_hash, receipt_hash

  def hash(data) do
    :crypto.hash(:sha3_512, data)
  end

  # --- Identity & key generation ---
  # Spec: pq_user.md §User creation

  def generate_identity do
    {sign_pkey, sign_skey} = generate_sign_keypair()
    {crypt_pkey, crypt_skey} = generate_crypt_keypair()

    %{
      sign_skey: sign_skey,
      sign_pkey: sign_pkey,
      crypt_skey: crypt_skey,
      crypt_pkey: crypt_pkey
    }
  end

  # Spec: pq_user.md §Algorithms — ML-DSA-87 (FIPS 204)
  def generate_sign_keypair do
    :crypto.generate_key(:mldsa87, [])
  end

  # Spec: pq_user.md §Algorithms — ML-KEM-1024 (FIPS 203)
  def generate_crypt_keypair do
    :crypto.generate_key(:mlkem1024, [])
  end

  # --- Signing ---
  # Spec: pq_user.md §Algorithms — ML-DSA-87 (FIPS 204)
  # Used for: crypt_cert, contact_cert, sign_b64 on all PQ tables

  def sign(data, sign_skey) do
    :crypto.sign(:mldsa87, :none, data, sign_skey)
  end

  def verify(data, signature, sign_pkey) do
    :crypto.verify(:mldsa87, :none, data, signature, sign_pkey)
  end

  # --- KEM ---
  # Spec: pq_dialogs.md §Key wrapping — ML-KEM-1024 (FIPS 203)
  # Used for: wrapping sender_msg_key to peer in dialog_keys

  def encapsulate_secret(recipient_crypt_pkey) do
    :crypto.encapsulate_key(:mlkem1024, recipient_crypt_pkey)
  end

  def decapsulate_secret(ciphertext, recipient_crypt_skey) do
    :crypto.decapsulate_key(:mlkem1024, recipient_crypt_skey, ciphertext)
  end

  # --- AES-256-GCM ---
  # Spec: pq_dialogs.md §Key derivation — AES-256-GCM (NIST SP 800-38D)
  # Spec: 07_content_polymorphism.md — blob format: nonce(12) || ciphertext || tag(16)
  # Used for: content_b64, refs_map_b64, type_b64, peer_wrapped_msg_key_b64

  @doc """
  Encrypts plaintext with AES-256-GCM under a 32-byte key.
  Returns `nonce(12) || ciphertext || tag(16)`.
  """
  def aes_gcm_encrypt(plaintext, <<key::binary-32>>) do
    nonce = :crypto.strong_rand_bytes(@aes_gcm_nonce_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        nonce,
        plaintext,
        <<>>,
        @aes_gcm_tag_size,
        true
      )

    nonce <> ciphertext <> tag
  end

  @doc """
  Decrypts an AES-256-GCM blob (`nonce || ciphertext || tag`) under a 32-byte key.
  Returns plaintext or `:error`.
  """
  def aes_gcm_decrypt(<<nonce::binary-12, ciphertext_and_tag::binary>>, <<key::binary-32>>) do
    ct_size = byte_size(ciphertext_and_tag) - @aes_gcm_tag_size
    <<ciphertext::binary-size(^ct_size), tag::binary-16>> = ciphertext_and_tag
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, <<>>, tag, false)
  end

  # --- HMAC ---
  # Spec: 09_symmetric_keys.md §Construction — HMAC-SHA3-256 as PRF inside HKDF
  # Spec: pq_dialogs.md §Reaction encryption — HMAC-SHA3-512 for reaction_hash

  def hmac_sha3_256(key, data) do
    :crypto.mac(:hmac, :sha3_256, key, data)
  end

  def hmac_sha3_512(key, data) do
    :crypto.mac(:hmac, :sha3_512, key, data)
  end

  # --- HKDF-SHA3-256 (RFC 5869) ---
  # Spec: 09_symmetric_keys.md — full construction, rationale, and invariants
  # Spec: pq_dialogs.md §Key derivation — sender_msg_key
  # Spec: pq_dialogs.md §Key wrapping — wrap_key from KEM shared secret

  @doc """
  HKDF Extract phase: concentrates input keying material into a fixed-length PRK.

      PRK = HMAC-SHA3-256(key = salt, data = ikm)
  """
  def hkdf_extract(ikm, salt) do
    :crypto.mac(:hmac, @hkdf_hash, salt, ikm)
  end

  @doc """
  HKDF Expand phase: derives `length` bytes of key material from a PRK.

      OKM = HMAC-SHA3-256(key = PRK, data = info || 0x01)   # first 32-byte block
  """
  def hkdf_expand(prk, info, length \\ @hkdf_hash_len) do
    1..ceil(length / @hkdf_hash_len)
    |> Enum.reduce({<<>>, <<>>}, fn i, {acc, prev} ->
      t = :crypto.mac(:hmac, @hkdf_hash, prk, prev <> info <> <<i::8>>)
      {acc <> t, t}
    end)
    |> elem(0)
    |> binary_part(0, length)
  end

  @doc """
  HKDF-SHA3-256 extract-then-expand (RFC 5869).

  Derives a fixed-length symmetric key from arbitrary input keying material,
  a domain-separation salt, and a context info label.

  ## Parameters

    - `ikm`    — input keying material (concatenated secrets)
    - `salt`   — non-secret domain-separation string
    - `info`   — context label distinguishing derived keys
    - `length` — output length in bytes (default 32)

  ## Dialog message key (pq_dialogs.md §Key derivation)

      ikm  = sign_skey <> crypt_skey <> peer_user_hash
      salt = "buckitup/dialog-mk/v1"
      info = "dialog-mk"

      sender_msg_key = EnigmaPq.hkdf_derive(ikm, salt, info)
      # => <<32 bytes>> — used for AES-256-GCM and HMAC in this dialog direction

  ## Dialog wrap key (pq_dialogs.md §Key wrapping)

      {shared_secret, kem_ciphertext} = EnigmaPq.encapsulate_secret(peer_crypt_pkey)

      wrap_key = EnigmaPq.hkdf_derive(shared_secret, "buckitup/dialog-wrap/v1", "wrap")
      wrapped  = EnigmaPq.aes_gcm_encrypt(sender_msg_key, wrap_key)
      # peer publishes {kem_ciphertext, wrapped} in dialog_keys

  ## Peer unwrap

      shared_secret = EnigmaPq.decapsulate_secret(kem_ciphertext, own_crypt_skey)
      wrap_key      = EnigmaPq.hkdf_derive(shared_secret, "buckitup/dialog-wrap/v1", "wrap")
      sender_msg_key = EnigmaPq.aes_gcm_decrypt(wrapped, wrap_key)

  """
  def hkdf_derive(ikm, salt, info, length \\ @hkdf_hash_len) do
    ikm |> hkdf_extract(salt) |> hkdf_expand(info, length)
  end
end

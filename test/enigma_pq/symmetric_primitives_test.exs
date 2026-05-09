defmodule EnigmaPq.SymmetricPrimitivesTest do
  use ExUnit.Case, async: true

  @aes_key :crypto.strong_rand_bytes(32)

  describe "aes_gcm_encrypt/2 and aes_gcm_decrypt/2" do
    test "round-trips plaintext" do
      plaintext = "hello, post-quantum world"
      blob = EnigmaPq.aes_gcm_encrypt(plaintext, @aes_key)
      assert EnigmaPq.aes_gcm_decrypt(blob, @aes_key) == plaintext
    end

    test "round-trips empty plaintext" do
      blob = EnigmaPq.aes_gcm_encrypt(<<>>, @aes_key)
      assert EnigmaPq.aes_gcm_decrypt(blob, @aes_key) == <<>>
    end

    test "round-trips large binary" do
      plaintext = :crypto.strong_rand_bytes(1_000_000)
      blob = EnigmaPq.aes_gcm_encrypt(plaintext, @aes_key)
      assert EnigmaPq.aes_gcm_decrypt(blob, @aes_key) == plaintext
    end

    test "blob is nonce(12) || ciphertext || tag(16)" do
      plaintext = "test"
      blob = EnigmaPq.aes_gcm_encrypt(plaintext, @aes_key)
      assert byte_size(blob) == 12 + byte_size(plaintext) + 16
    end

    test "different encryptions of same plaintext produce different blobs" do
      plaintext = "determinism check"
      blob_a = EnigmaPq.aes_gcm_encrypt(plaintext, @aes_key)
      blob_b = EnigmaPq.aes_gcm_encrypt(plaintext, @aes_key)
      assert blob_a != blob_b
    end

    test "wrong key returns :error" do
      blob = EnigmaPq.aes_gcm_encrypt("secret", @aes_key)
      wrong_key = :crypto.strong_rand_bytes(32)
      assert EnigmaPq.aes_gcm_decrypt(blob, wrong_key) == :error
    end

    test "tampered ciphertext returns :error" do
      blob = EnigmaPq.aes_gcm_encrypt("secret", @aes_key)
      <<nonce::binary-12, rest::binary>> = blob
      tampered = nonce <> :crypto.exor(rest, :crypto.strong_rand_bytes(byte_size(rest)))
      assert EnigmaPq.aes_gcm_decrypt(tampered, @aes_key) == :error
    end
  end

  describe "hmac_sha3_256/2" do
    test "produces 32-byte MAC" do
      mac = EnigmaPq.hmac_sha3_256("key", "data")
      assert byte_size(mac) == 32
    end

    test "deterministic" do
      assert EnigmaPq.hmac_sha3_256("k", "d") == EnigmaPq.hmac_sha3_256("k", "d")
    end

    test "different keys produce different MACs" do
      refute EnigmaPq.hmac_sha3_256("key_a", "data") == EnigmaPq.hmac_sha3_256("key_b", "data")
    end
  end

  describe "hmac_sha3_512/2" do
    test "produces 64-byte MAC" do
      mac = EnigmaPq.hmac_sha3_512("key", "data")
      assert byte_size(mac) == 64
    end

    test "deterministic" do
      assert EnigmaPq.hmac_sha3_512("k", "d") == EnigmaPq.hmac_sha3_512("k", "d")
    end
  end

  describe "HKDF-SHA3-256" do
    test "hkdf_extract produces 32-byte PRK" do
      prk = EnigmaPq.hkdf_extract("input key material", "salt")
      assert byte_size(prk) == 32
    end

    test "hkdf_expand produces requested length" do
      prk = :crypto.strong_rand_bytes(32)
      assert byte_size(EnigmaPq.hkdf_expand(prk, "info")) == 32
      assert byte_size(EnigmaPq.hkdf_expand(prk, "info", 64)) == 64
      assert byte_size(EnigmaPq.hkdf_expand(prk, "info", 16)) == 16
    end

    test "hkdf_derive is extract-then-expand" do
      ikm = :crypto.strong_rand_bytes(64)
      salt = "test-salt"
      info = "test-info"

      manual = ikm |> EnigmaPq.hkdf_extract(salt) |> EnigmaPq.hkdf_expand(info)
      derived = EnigmaPq.hkdf_derive(ikm, salt, info)
      assert manual == derived
    end

    test "different salts produce different keys" do
      ikm = :crypto.strong_rand_bytes(32)
      key_a = EnigmaPq.hkdf_derive(ikm, "salt-a", "info")
      key_b = EnigmaPq.hkdf_derive(ikm, "salt-b", "info")
      refute key_a == key_b
    end

    test "different info labels produce different keys" do
      ikm = :crypto.strong_rand_bytes(32)
      key_a = EnigmaPq.hkdf_derive(ikm, "salt", "info-a")
      key_b = EnigmaPq.hkdf_derive(ikm, "salt", "info-b")
      refute key_a == key_b
    end

    test "dialog sender_msg_key derivation per spec" do
      alice = EnigmaPq.generate_identity()
      bob = EnigmaPq.generate_identity()

      sender_msg_key = derive_sender_msg_key(alice, bob.sign_pkey)
      assert byte_size(sender_msg_key) == 32

      same_key = derive_sender_msg_key(alice, bob.sign_pkey)
      assert sender_msg_key == same_key
    end

    test "dialog wrap_key derivation per spec" do
      bob = EnigmaPq.generate_identity()
      {shared_secret, _ciphertext} = EnigmaPq.encapsulate_secret(bob.crypt_pkey)

      wrap_key = derive_wrap_key(shared_secret)
      assert byte_size(wrap_key) == 32
    end
  end

  describe "integration: wrap/unwrap sender_msg_key" do
    test "sender wraps msg_key for peer, peer unwraps it" do
      bob = EnigmaPq.generate_identity()
      sender_msg_key = :crypto.strong_rand_bytes(32)

      {kem_ciphertext, wrapped} = wrap_for_peer(sender_msg_key, bob.crypt_pkey)
      recovered = unwrap_from_sender(kem_ciphertext, wrapped, bob.crypt_skey)

      assert recovered == sender_msg_key
    end
  end

  describe "integration: encrypt/decrypt dialog message" do
    test "full message round-trip with derived sender_msg_key" do
      alice = EnigmaPq.generate_identity()
      bob = EnigmaPq.generate_identity()
      sender_msg_key = derive_sender_msg_key(alice, bob.sign_pkey)

      message = Jason.encode!("hello Bob")
      content_b64 = EnigmaPq.aes_gcm_encrypt(message, sender_msg_key)
      decrypted = EnigmaPq.aes_gcm_decrypt(content_b64, sender_msg_key)

      assert Jason.decode!(decrypted) == "hello Bob"
    end
  end

  # Helpers — used across multiple describe blocks

  defp user_hash_from_sign_pkey(sign_pkey) do
    "u_" <> Base.encode16(EnigmaPq.hash(sign_pkey), case: :lower)
  end

  defp derive_sender_msg_key(sender_identity, peer_sign_pkey) do
    ikm =
      sender_identity.sign_skey <>
        sender_identity.crypt_skey <>
        user_hash_from_sign_pkey(peer_sign_pkey)

    EnigmaPq.hkdf_derive(ikm, "buckitup/dialog-mk/v1", "dialog-mk")
  end

  defp derive_wrap_key(shared_secret) do
    EnigmaPq.hkdf_derive(shared_secret, "buckitup/dialog-wrap/v1", "wrap")
  end

  defp wrap_for_peer(sender_msg_key, peer_crypt_pkey) do
    {shared_secret, kem_ciphertext} = EnigmaPq.encapsulate_secret(peer_crypt_pkey)
    wrapped = EnigmaPq.aes_gcm_encrypt(sender_msg_key, derive_wrap_key(shared_secret))
    {kem_ciphertext, wrapped}
  end

  defp unwrap_from_sender(kem_ciphertext, wrapped, own_crypt_skey) do
    shared_secret = EnigmaPq.decapsulate_secret(kem_ciphertext, own_crypt_skey)
    EnigmaPq.aes_gcm_decrypt(wrapped, derive_wrap_key(shared_secret))
  end
end

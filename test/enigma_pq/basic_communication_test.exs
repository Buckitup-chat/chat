defmodule EnigmaPq.BasicCommunicationTest do
  use ExUnit.Case, async: true
  alias EnigmaPq

  # Prefix constants as defined in requirements
  @user_hash_prefix <<0x01>>
  @dialog_hash_prefix <<0x02>>

  setup do
    # Check if crypto supports the required algorithms
    # This might fail on older OTP versions, but we assume OTP 28 as per request
    # :crypto.info_lib() returns a list of maps of loaded libraries
    if :crypto.info_lib() == [] do
      # This technically shouldn't happen if crypto is loaded
      :ok
    else
      :ok
    end
  end

  test "Alice generates identity and certificate" do
    # 1. Generate Alice's identity
    alice = EnigmaPq.generate_identity()

    assert is_binary(alice.sign_pkey)
    assert is_binary(alice.sign_skey)
    assert is_binary(alice.crypt_pkey)
    assert is_binary(alice.crypt_skey)

    # 2. Create Certificate: Alice signs her encryption public key with her signing secret key
    crypt_pkey_cert = EnigmaPq.sign(alice.crypt_pkey, alice.sign_skey)
    assert is_binary(crypt_pkey_cert)

    # 3. Verify Certificate: Anyone should be able to verify using Alice's signing public key
    assert EnigmaPq.verify(alice.crypt_pkey, crypt_pkey_cert, alice.sign_pkey)

    # 4. Verify User Hash generation (Prefix check)
    # The requirement says User Hash is SHA3-512 with 0x01 prefix.
    # EnigmaPq.hash/1 returns raw SHA3-512.
    # We verify that we can construct the correct format.
    raw_hash = EnigmaPq.hash(alice.sign_pkey) # Example data to hash
    user_hash = @user_hash_prefix <> raw_hash

    assert byte_size(user_hash) == 1 + 64 # 1 byte prefix + 64 bytes (512 bits)
    assert String.starts_with?(user_hash, @user_hash_prefix)
  end

  test "Alice and Bob secure communication flow" do
    # 1. Setup Identities
    alice = EnigmaPq.generate_identity()
    bob = EnigmaPq.generate_identity()

    # 2. Key Encapsulation (Alice wants to send secret to Bob)
    # Alice uses Bob's encryption public key
    {shared_secret_alice, ciphertext} = EnigmaPq.encapsulate_secret(bob.crypt_pkey)

    assert is_binary(shared_secret_alice)
    assert is_binary(ciphertext)

    # 3. Signing the Ciphertext (Alice proves she sent it)
    # Alice signs the ciphertext with her signing secret key
    signature = EnigmaPq.sign(ciphertext, alice.sign_skey)
    assert is_binary(signature)

    # 4. Bob receives: ciphertext, signature, alice.sign_pkey
    # Bob verifies the signature first
    is_valid_sender = EnigmaPq.verify(ciphertext, signature, alice.sign_pkey)
    assert is_valid_sender

    # 5. Bob decapsulates the shared secret
    shared_secret_bob = EnigmaPq.decapsulate_secret(ciphertext, bob.crypt_skey)

    # 6. Verify shared secrets match
    assert shared_secret_bob == shared_secret_alice
  end

  test "Dialog Hash format verification" do
    # Verify we can construct Dialog Hash with 0x02 prefix
    data = "alice_and_bob_dialog"
    raw_hash = EnigmaPq.hash(data)
    dialog_hash = @dialog_hash_prefix <> raw_hash

    assert byte_size(dialog_hash) == 1 + 64
    assert String.starts_with?(dialog_hash, @dialog_hash_prefix)
  end
end

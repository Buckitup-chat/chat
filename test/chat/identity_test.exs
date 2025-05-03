defmodule Chat.IdentityTest do
  use ExUnit.Case, async: true

  alias Chat.Identity

  describe "create/1" do
    test "creates an identity with the given name" do
      name = "Test User"
      identity = Identity.create(name)

      assert %Identity{} = identity
      assert identity.name == name
      assert is_binary(identity.private_key)
      assert is_binary(identity.public_key)
      assert byte_size(identity.private_key) == 32
      assert byte_size(identity.public_key) == 33
    end
  end

  describe "pub_key/1" do
    test "returns the public key of the identity" do
      identity = Identity.create("Test User")
      assert Identity.pub_key(identity) == identity.public_key
    end
  end

  describe "to_strings/1" do
    test "converts an identity to a list of strings" do
      identity = Identity.create("Test User")
      [name, key_str] = Identity.to_strings(identity)

      assert name == "Test User"
      assert is_binary(key_str)

      # Verify that the key string can be decoded back to the original keys
      decoded = Base.decode64!(key_str)
      # 32 bytes private key + 33 bytes public key
      assert byte_size(decoded) == 65
    end
  end

  describe "priv_key_to_string/1" do
    test "converts an identity's private key to a string" do
      identity = Identity.create("Test User")
      key_str = Identity.priv_key_to_string(identity)

      assert is_binary(key_str)

      # Verify that the key string can be decoded
      decoded = Base.decode64!(key_str)
      # 32 bytes private key + 33 bytes public key
      assert byte_size(decoded) == 65
    end
  end

  describe "from_strings/1" do
    test "creates an identity from a list of strings" do
      original = Identity.create("Test User")
      strings = Identity.to_strings(original)

      identity = Identity.from_strings(strings)

      assert %Identity{} = identity
      assert identity.name == original.name
      assert identity.private_key == original.private_key
      assert identity.public_key == original.public_key
    end
  end

  describe "from_keys/1" do
    test "creates an identity from a map with private and public keys" do
      original = Identity.create("Test User")
      keys = %{private_key: original.private_key, public_key: original.public_key}

      identity = Identity.from_keys(keys)

      assert %Identity{} = identity
      assert identity.name == ""
      assert identity.private_key == original.private_key
      assert identity.public_key == original.public_key
    end
  end

  describe "Enigma.Hash.Protocol implementation" do
    test "to_iodata/1 returns the public key" do
      identity = Identity.create("Test User")
      assert Enigma.Hash.Protocol.to_iodata(identity) == identity.public_key
    end
  end
end

defmodule BucketTest.IdentityTest do
  use ExUnit.Case, async: true
  doctest Bucket.Identity

  alias Bucket.Identity

  test "can sign a message" do
    message = "Hello World!"

    signed = Identity.digest(message)

    assert is_binary(signed)

    assert Enigma.P256.valid_sign?(message, signed, Identity.get_pub_key())
  end

  test "can calculate secret" do
    identity_pub_key = Identity.get_pub_key()
    other_private_key = Enigma.P256.generate_key()
    other_pub_key = Enigma.P256.derive_public_key(other_private_key)

    correct_secret = Enigma.P256.ecdh(other_private_key, identity_pub_key)

    assert correct_secret == Identity.compute_secret(other_pub_key)
  end

  test "integrity ready call is forbidden" do
    assert_raise RuntimeError, fn -> Identity.ready?() end
  end
end

defmodule Enigma.CiperedTest do
  use ExUnit.Case, async: true

  test "plain ciphering should work" do
    {alice_priv_key, alice_pub_key} = Enigma.generate_keys()
    {bob_priv_key, bob_pub_key} = Enigma.generate_keys()

    alice_secret = Enigma.compute_secret(alice_priv_key, bob_pub_key)
    bob_secret = Enigma.compute_secret(bob_priv_key, alice_pub_key)

    assert alice_secret == bob_secret

    msg = "Hi there"

    deciphered_msg =
      msg
      |> Enigma.cipher(alice_secret)
      |> Enigma.decipher(bob_secret)

    assert msg == deciphered_msg
  end
end

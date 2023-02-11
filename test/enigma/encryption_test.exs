defmodule Enigma.EncryptionTest do
  use ExUnit.Case, async: true

  test "plain flow should work" do
    {alice_priv_key, alice_pub_key} = Enigma.generate_keys()
    {bob_priv_key, bob_pub_key} = Enigma.generate_keys()

    message = "Some secret message"

    decrypted_message =
      message
      |> Enigma.encrypt(alice_priv_key, bob_pub_key)
      |> Enigma.decrypt(bob_priv_key, alice_pub_key)

    assert message == decrypted_message
  end

  test "signed flow should work as well" do
    {alice_priv_key, alice_pub_key} = Enigma.generate_keys()
    {bob_priv_key, bob_pub_key} = Enigma.generate_keys()

    message = "Some secret message"

    {encrypted, sign} = Enigma.encrypt_and_sign(message, alice_priv_key, bob_pub_key)

    assert {:ok, ^message} = Enigma.decrypt_signed({encrypted, sign}, bob_priv_key, alice_pub_key)
    assert :error = Enigma.decrypt_signed({encrypted, sign}, bob_priv_key, bob_pub_key)
  end

  test "generated secret should be same size and do not repeat" do
    first_secret = Enigma.generate_secret()
    second_secret = Enigma.generate_secret()

    assert first_secret != second_secret

    assert [first_secret, second_secret] |> Enum.all?(&(byte_size(&1) == 32))
  end
end

defmodule Chat.SigningTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.User

  test "Alice to Bob signature should work" do
    alice = %{private_key: alice_priv} = User.login("Alice")
    bob = %{private_key: bob_priv} = User.login("Bob")

    _alice_card = %{pub_key: alice_pub} = Card.from_identity(alice)
    _bob_card = %{pub_key: bob_pub} = Card.from_identity(bob)

    plain_message = "Hi there"

    for_bob = Enigma.encrypt_and_sign(plain_message, alice_priv, bob_pub)
    {:ok, bob_message} = Enigma.decrypt_signed(for_bob, bob_priv, alice_pub, alice_pub)
    assert bob_message == plain_message
  end

  # test "Anyone should be able to check that Alice message to Bob was signed by Alice" do
  #   alice = User.login("Alice")
  #   bob = User.login("Bob")

  #   alice_card = Card.from_identity(alice)
  #   bob_card = Card.from_identity(bob)

  #   signed_message =
  #     "Hi there"
  #     |> Utils.encrypt(bob_card)
  #     |> then(&{&1, &1 |> Utils.sign(alice)})

  #   assert signed_message
  #          |> then(fn {msg, sign} -> sign |> Utils.is_signed_by?(msg, alice_card) end)
  # end
end

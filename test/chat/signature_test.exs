defmodule Chat.SigningTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.User
  alias Chat.Utils

  test "Alice to Bob signature should work" do
    alice = %{priv_key: alice_priv} = User.login("Alice")
    bob = %{priv_key: bob_priv} = User.login("Bob")

    _alice_card = %{pub_key: alice_pub} = Card.from_identity(alice)
    _bob_card = %{pub_key: bob_pub} = Card.from_identity(bob)

    plain_message = "Hi there"

    for_bob = Utils.encrypt(plain_message, bob_pub)
    bob_message = Utils.decrypt(for_bob, bob_priv)
    assert bob_message == plain_message

    signature = for_bob |> Utils.sign(alice_priv)
    assert signature |> Utils.is_signed_by?(for_bob, alice_pub)
  end

  test "Anyone should be able to check that Alice message to Bob was signed by Alice" do
    alice = User.login("Alice")
    bob = User.login("Bob")

    alice_card = Card.from_identity(alice)
    bob_card = Card.from_identity(bob)

    signed_message =
      "Hi there"
      |> Utils.encrypt(bob_card)
      |> then(&{&1, &1 |> Utils.sign(alice)})

    assert signed_message
           |> then(fn {msg, sign} -> sign |> Utils.is_signed_by?(msg, alice_card) end)
  end
end

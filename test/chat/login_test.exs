defmodule Chat.LoginTest do
  use ExUnit.Case, async: true

  alias Chat.User

  test "login with no identity" do
    correct_name = "Some Name Here"

    assert %User.Identity{name: ^correct_name} = User.login(correct_name)
  end

  test "login with identity" do
    me = User.Identity.create("Some Name")

    assert ^me = User.login(me)
  end

  test "message passing" do
    alice = "Alice" |> User.Identity.create()
    alice_card = alice |> User.Card.from_identity()

    message = "some message in string"

    assert User.encrypt(message, alice_card) != message

    assert ^message = message |> User.encrypt(alice_card) |> User.decrypt(alice)
  end
end

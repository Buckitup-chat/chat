defmodule Chat.LoginTest do
  use ExUnit.Case, async: true

  alias Chat.User
  alias Chat.Utils

  test "login with no identity" do
    correct_name = "Some Name Here"

    assert %Chat.Identity{name: ^correct_name} = User.login(correct_name)
  end

  test "login with identity" do
    me = Chat.Identity.create("Some Name")

    assert ^me = User.login(me)
  end

  test "message passing" do
    alice = "Alice" |> Chat.Identity.create()
    alice_card = alice |> Chat.Card.from_identity()

    message = "some message in string"

    assert Utils.encrypt(message, alice_card) != message

    assert ^message = message |> Utils.encrypt(alice_card) |> Utils.decrypt(alice)

    assert ~s|#Chat.Identity<name: "#{alice.name}", ...>| == inspect(alice)

    assert ~s|#Chat.Card<name: "#{alice_card.name}", hash: "#{alice_card.hash}", ...>| ==
             inspect(alice_card)
  end

  test "device codec" do
    alice = "Alice" |> User.login()

    decoded =
      alice
      |> User.device_encode()
      |> User.device_decode()

    assert {^alice, []} = decoded
  end
end

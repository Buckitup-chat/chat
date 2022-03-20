defmodule Chat.Dialogs.DialogTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identitiy
  alias Chat.User

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    charlie = User.login("Charlie")

    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)
      |> Dialogs.add_text(alice, text_message, DateTime.utc_now())
      |> Dialogs.add_image(alice, {"not_image", "text/plain"})
      |> Dialogs.add_image(bob, {"not_image 2", "text/plain"}, DateTime.utc_now())

    assert 3 == Enum.count(dialog.messages)

    glimpse = dialog |> Dialogs.glimpse()

    assert 1 == Enum.count(glimpse.messages)

    assert_raise RuntimeError, fn -> dialog |> Dialogs.add_text(charlie, "spam") end

    assert_raise(RuntimeError, fn -> dialog |> Dialogs.read(charlie) end)
  end
end

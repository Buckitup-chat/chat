defmodule Chat.Dialogs.MessageTest do
  use ExUnit.Case, async: true

  alias Chat.Dialogs
  alias Chat.User

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")

    bob_card = bob |> User.Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.Dialog.start(bob_card)
      |> Dialogs.Dialog.add_text(alice, text_message)

    assert 1 == Enum.count(dialog.messages)

    message = dialog.messages |> Enum.at(0)

    assert text_message == message.a_copy |> User.decrypt(alice)
    assert text_message == message.b_copy |> User.decrypt(bob)

    assert_raise ErlangError, fn -> message.a_copy |> User.decrypt(bob) end
  end
end

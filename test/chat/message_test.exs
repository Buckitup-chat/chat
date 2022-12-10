defmodule Chat.Dialogs.MessageTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Messages.Text
  alias Chat.User

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")

    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    %Text{text: text_message}
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    dialog_messages = Dialogs.read(dialog, alice)

    assert 1 == Enum.count(dialog_messages)

    message = dialog_messages |> Enum.at(0)

    assert text_message == message.content
  end

  test "read dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"
    bob_answer = "Bob welcomes Alice too"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    %Text{text: text_message} |> Dialogs.add_new_message(alice, dialog)
    %Text{text: bob_answer} |> Dialogs.add_new_message(bob, dialog) |> Dialogs.await_saved(dialog)

    bob_version =
      dialog
      |> Dialogs.read(bob)

    assert 2 == bob_version |> Enum.count()

    assert bob_answer == bob_version |> Enum.at(1) |> then(& &1.content)
    assert bob_version |> Enum.at(1) |> then(& &1.is_mine?)

    alice_version =
      dialog
      |> Dialogs.read(alice)

    assert 2 == alice_version |> Enum.count()

    assert bob_answer == alice_version |> Enum.at(1) |> then(& &1.content)
    assert false == alice_version |> Enum.at(1) |> then(& &1.is_mine?)

    short_bob_version =
      dialog
      |> Dialogs.read(bob, {nil, 0}, 1)

    assert 1 == short_bob_version |> Enum.count()
    assert bob_answer == short_bob_version |> Enum.at(0) |> then(& &1.content)

    short_bob_version_cont =
      dialog
      |> Dialogs.read(bob, {2, 0})

    assert 1 == short_bob_version_cont |> Enum.count()
    assert text_message == short_bob_version_cont |> Enum.at(0) |> then(& &1.content)
  end
end

defmodule Chat.Dialogs.MessageTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.User
  alias Chat.Utils

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")

    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)
      |> Dialogs.add_text(alice, text_message)

    assert 1 == Enum.count(dialog.messages)

    message = dialog.messages |> Enum.at(0)

    assert text_message == message.a_copy |> Utils.decrypt(alice)
    assert text_message == message.b_copy |> Utils.decrypt(bob)

    assert_raise ErlangError, fn -> message.a_copy |> Utils.decrypt(bob) end

    bob_answer = "Bob welcomes Alice too"

    dialog =
      dialog
      |> Dialogs.add_text(bob, bob_answer)

    assert 2 == Enum.count(dialog.messages)

    message = dialog.messages |> Enum.reverse() |> Enum.at(1)

    assert bob_answer == message.a_copy |> Utils.decrypt(alice)
    assert bob_answer == message.b_copy |> Utils.decrypt(bob)
  end

  test "read dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"
    bob_answer = "Bob welcomes Alice too"

    start_time = DateTime.utc_now() |> DateTime.add(-10)
    second_time = start_time |> DateTime.add(5)

    dialog =
      alice
      |> Dialogs.open(bob_card)
      |> Dialogs.add_text(alice, text_message, start_time)
      |> Dialogs.add_text(bob, bob_answer, second_time)

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
      |> Dialogs.read(bob, DateTime.utc_now() |> DateTime.to_unix(), 1)

    assert 1 == short_bob_version |> Enum.count()
    assert bob_answer == short_bob_version |> Enum.at(0) |> then(& &1.content)

    short_bob_version_cont =
      dialog
      |> Dialogs.read(bob, second_time |> DateTime.to_unix())

    assert 1 == short_bob_version_cont |> Enum.count()
    assert text_message == short_bob_version_cont |> Enum.at(0) |> then(& &1.content)
  end
end

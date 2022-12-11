defmodule Chat.OrderingTest do
  use ExUnit.Case, async: false

  alias Chat.Card
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Ordering
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "should provide 1 on new key" do
    assert 1 = Ordering.next({:some, "key"})
  end

  test "should provide next key on existing dialog message" do
    dialog_key_preix = messaged_dialog_key_prefix()

    assert 1 < Ordering.next(dialog_key_preix)
  end

  test "should provide next key on existing room message" do
    room_msg_prefix = prefix_for_room_with_5_msgs()

    assert 5 = Ordering.last(room_msg_prefix)
    assert 6 = Ordering.next(room_msg_prefix)

    Ordering.reset()

    assert 5 = Ordering.last(room_msg_prefix)
    assert 6 = Ordering.next(room_msg_prefix)
  end

  defp messaged_dialog_key_prefix do
    user = User.login("some")

    dialog = Dialogs.find_or_open(user, user |> Card.from_identity())

    %Chat.Messages.Text{text: "some message"}
    |> Dialogs.add_new_message(user, dialog)

    {:dialog_message, dialog |> Dialogs.Dialog.dialog_key()}
  end

  defp prefix_for_room_with_5_msgs do
    alice = User.login("Alice")
    alice |> User.register()

    room_identity = alice |> Rooms.add("some room")
    room = Rooms.Room.create(alice, room_identity)

    message = "hello, room  "

    last =
      for num <- 1..5 do
        message
        |> Kernel.<>(to_string(num))
        |> Messages.Text.new(num)
        |> Rooms.add_new_message(alice, room.pub_key)
      end
      |> List.last()
      |> elem(1)

    ChangeTracker.await(
      {:room_message, room.pub_key |> Utils.binhash(), last.timestamp, last.id |> Utils.binhash()}
    )

    {:room_message, room.pub_key |> Utils.binhash()}
  end
end

defmodule Chat.StructuresTest do
  use ExUnit.Case, async: true

  test "dialog message" do
    struct = %Chat.Dialogs.Message{timestamp: 1, is_a_to_b?: false, content: 23, id: 4}

    assert "#Chat.Dialogs.Message<timestamp: 1, is_a_to_b?: false, type: nil, id: 4, ...>" ==
             inspect(struct)
  end

  test "dialog.dialog" do
    struct = %Chat.Dialogs.Dialog{a_key: 1, b_key: 2}

    assert "#Chat.Dialogs.Dialog<...>" ==
             inspect(struct)
  end

  test "card" do
    struct = %Chat.Card{name: 1, pub_key: 2}

    assert "#Chat.Card<name: 1, ...>" ==
             inspect(struct)
  end

  test "dialog.private_message" do
    struct = %Chat.Dialogs.PrivateMessage{
      timestamp: 1,
      is_mine?: false,
      content: 2,
      type: 3,
      id: 4,
      index: 5
    }

    assert "%Chat.Dialogs.PrivateMessage{timestamp: 1, index: 5, type: 3, content: 2, is_mine?: false, id: 4}" ==
             inspect(struct)
  end

  test "actor" do
    struct = %Chat.Actor{me: 1, rooms: [2, 3]}

    assert "%Chat.Actor{me: 1, rooms: [2, 3], contacts: %{}}" == inspect(struct)
  end

  test "room.message" do
    struct = %Chat.Rooms.Message{timestamp: 0, author_key: 1, encrypted: 2, type: 3, id: 4}

    assert "%Chat.Rooms.Message{timestamp: 0, author_key: 1, encrypted: 2, type: 3, id: 4, version: 1}" ==
             inspect(struct)
  end
end

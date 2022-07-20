defmodule Chat.StructuresTest do
  use ExUnit.Case, async: true

  test "dialog message" do
    struct = %Chat.Dialogs.Message{timestamp: 1, is_a_to_b?: false, a_copy: 2, b_copy: 3, id: 4}

    assert "#Chat.Dialogs.Message<id: 4, is_a_to_b?: false, timestamp: 1, type: nil, ...>" ==
             inspect(struct)
  end

  test "dialog.dialog" do
    struct = %Chat.Dialogs.Dialog{a_key: 1, b_key: 2}

    assert "#Chat.Dialogs.Dialog<...>" ==
             inspect(struct)
  end

  test "card" do
    struct = %Chat.Card{name: 1, pub_key: 2, hash: 3}

    assert "#Chat.Card<hash: 3, name: 1, ...>" ==
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

    assert "%Chat.Dialogs.PrivateMessage{content: 2, id: 4, index: 5, is_mine?: false, timestamp: 1, type: 3}" ==
             inspect(struct)
  end

  test "actor" do
    struct = %Chat.Actor{me: 1, rooms: [2, 3]}

    assert "%Chat.Actor{contacts: %{}, me: 1, rooms: [2, 3]}" == inspect(struct)
  end

  test "room.message" do
    struct = %Chat.Rooms.Message{timestamp: 0, author_hash: 1, encrypted: 2, type: 3, id: 4}

    assert "%Chat.Rooms.Message{author_hash: 1, encrypted: 2, id: 4, timestamp: 0, type: 3, version: 1}" ==
             inspect(struct)
  end
end

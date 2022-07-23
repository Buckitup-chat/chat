defmodule Chat.LogTest do
  use ExUnit.Case, async: false

  alias Chat.Card
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  alias Chat.Log

  setup do
    Chat.Db.db() |> CubDB.clear()
  end

  test "login related logs should save correct" do
    me = User.login("me")

    Log.sign_in(me, 1)
    Log.visit(me, 2)
    Log.self_backup(me, 3)
    Log.export_keys(me, 4)
    Log.logout(me, 5)

    assert {entries, 0} = Log.list()
    assert 5 = entries |> Enum.count()
  end

  test "dialog related logs should save correct" do
    me = User.login("me")
    bob = User.login("bob")
    bob_card = Card.from_identity(bob)

    Log.open_direct(me, 1, bob_card)
    Log.message_direct(me, 2, bob_card)
    Log.update_message_direct(me, 3, bob_card)
    Log.delete_message_direct(me, 4, bob_card)

    assert {entries, 0} = Log.list()
    assert 4 = entries |> Enum.count()
  end

  test "room related logs should save correct" do
    me = User.login("me")
    room_identity = Rooms.add(me, "Room name")
    room = Rooms.get(room_identity |> Utils.hash())

    Log.create_room(me, 1, room.pub_key, room.type)
    Log.message_room(me, 2, room.pub_key)
    Log.update_room_message(me, 3, room.pub_key)
    Log.delete_room_message(me, 4, room.pub_key)
    Log.visit_room(me, 5, room.pub_key)
    Log.request_room_key(me, 6, room.pub_key)

    assert {entries, 0} = Log.list()
    assert 6 = entries |> Enum.count()
  end

  test "message humanization should work well for all types" do
    me = User.login("me")

    Log.sign_in(me, 1)
    assert {[{_, {_, action}}], 0} = Log.list()

    assert "signs in" = Log.humanize_action(action)
    assert "unknown act" = Log.humanize_action(:some_strange_unlisted_action)
  end
end

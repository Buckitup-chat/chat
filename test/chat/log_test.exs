defmodule Chat.LogTest do
  use ExUnit.Case, async: false

  alias Chat.Card
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Identity
  alias Chat.Ordering
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  alias Chat.Log

  setup_all do
    Db.db()
    |> CubDB.clear()
  end

  test "login related logs should save correct" do
    me = User.login("me")
    base = Ordering.last({:action_log})

    assert_added(5, fn ->
      Log.sign_in(me, base + 1)
      Log.visit(me, base + 2)
      Log.self_backup(me, base + 3)
      Log.export_keys(me, base + 4)
      Log.logout(me, base + 5)

      await(me, base + 5)
    end)
  end

  test "dialog related logs should save correct" do
    me = User.login("me")
    bob = User.login("bob")
    bob_card = Card.from_identity(bob)
    base = Ordering.last({:action_log})

    assert_added(4, fn ->
      Log.open_direct(me, base + 1, bob_card)
      Log.message_direct(me, base + 2, bob_card)
      Log.update_message_direct(me, base + 3, bob_card)
      Log.delete_message_direct(me, base + 4, bob_card)

      await(me, base + 4)
    end)
  end

  test "room related logs should save correct" do
    me = User.login("me")
    {room_identity, _room} = Rooms.add(me, "Room name")
    ChangeTracker.await({:rooms, room_identity |> Identity.pub_key() |> Utils.hash()})
    room = Rooms.get(room_identity |> Utils.hash())
    base = Ordering.last({:action_log})

    assert_added(6, fn ->
      Log.create_room(me, base + 1, room.pub_key, room.type)
      Log.message_room(me, base + 2, room.pub_key)
      Log.update_room_message(me, base + 3, room.pub_key)
      Log.delete_room_message(me, base + 4, room.pub_key)
      Log.visit_room(me, base + 5, room.pub_key)
      Log.request_room_key(me, base + 6, room.pub_key)

      await(me, base + 6)
    end)
  end

  test "message humanization should work well for all types" do
    me = User.login("me")

    await()
    base = Ordering.last({:action_log})
    Log.sign_in(me, base + 1)
    await()
    assert {_, {_, action}} = Log.list() |> elem(0) |> List.first()

    assert "signs in" = Log.humanize_action(action)
    assert "unknown act" = Log.humanize_action(:some_strange_unlisted_action)
  end

  defp await do
    ChangeTracker.await()
  end

  defp await(user, index) do
    ChangeTracker.await({:action_log, index, user |> Utils.binhash()})
  end

  defp assert_added(count, action) do
    {entries, 0} = Log.list()
    before = entries |> Enum.count()

    action.()

    {entries, 0} = Log.list()
    now = entries |> Enum.count()

    assert count == now - before
  end
end

defmodule Chat.Rooms.RoomsBrokerTest do
  use ChatWeb.DataCase, async: false

  alias Chat.Db.ChangeTracker
  alias Chat.Rooms
  alias Chat.Rooms.RoomsBroker
  alias Chat.User

  test "sync loads registered rooms and forget drops one" do
    alice = User.login("Alice")
    {room_identity, room} = alice |> Rooms.add("broker room #{UUID.uuid4()}")
    Rooms.await_saved(room_identity)
    ChangeTracker.await()

    assert :ok == RoomsBroker.sync()
    assert room.pub_key in listed_keys()

    RoomsBroker.forget(room.pub_key)

    refute room.pub_key in listed_keys()
  end

  defp listed_keys do
    {my, other} = RoomsBroker.list(%{})

    (my ++ other) |> Enum.map(& &1.pub_key)
  end
end

defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Rooms
  alias Chat.User

  test "room creation" do
    alice = User.login("Alice")
    alice_hash = alice |> User.pub_key() |> Chat.Utils.hash()

    room_name = "Alice's room"

    room = alice |> Rooms.add(room_name)

    assert %Rooms.Room{} = room

    assert ~s|#Chat.Rooms.Room<messages: [], name: "#{room_name}", users: ["#{alice_hash}"], ...>| =
             inspect(room)
  end
end

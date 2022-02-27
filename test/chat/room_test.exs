defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Rooms
  alias Chat.User

  test "room creation" do
    alice = User.login("Alice")
    alice_hash = alice |> User.pub_key() |> Chat.Utils.hash()

    room_name = "Alice's room"

    room_identity = alice |> Rooms.add(room_name)

    room = Rooms.Room.create(alice, room_identity)

    assert %Rooms.Room{} = room

    correct =
      ~s|#Chat.Rooms.Room<messages: [], name: "#{room_name}", users: ["#{alice_hash}"], ...>|

    assert correct == inspect(room)
  end
end

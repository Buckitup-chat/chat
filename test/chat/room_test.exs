defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "room creation" do
    alice = User.login("Alice")
    alice_hash = alice |> User.pub_key() |> Utils.hash()

    room_name = "Alice's room"

    room_identity = alice |> Rooms.add(room_name)

    room = Rooms.Room.create(alice, room_identity)

    assert %Rooms.Room{} = room

    correct =
      ~s|#Chat.Rooms.Room<messages: [], name: "#{room_name}", users: ["#{alice_hash}"], ...>|

    assert correct == inspect(room)
  end

  test "room messages" do
    alice = User.login("Alice")
    alice_hash = alice |> Identity.pub_key() |> Utils.hash()

    room_identity = alice |> Rooms.add("some room")
    room = Rooms.Room.create(alice, room_identity)

    message = "hello, room"
    updated_room = Rooms.Room.add_text(room, alice, message)

    assert %Rooms.Room{messages: [%Rooms.Message{author_hash: ^alice_hash, type: :text}]} =
             updated_room
  end
end

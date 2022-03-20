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
    updated_room = Rooms.add_text(room, alice, message)

    assert %Rooms.Room{messages: [%Rooms.Message{author_hash: ^alice_hash, type: :text}]} =
             updated_room

    assert [%Rooms.PlainMessage{content: ^message, type: :text, author_hash: ^alice_hash}] =
             updated_room |> Rooms.read(room_identity)
  end

  test "room invite" do
    alice = User.login("Alice")

    room_identity = alice |> Rooms.add("some room")
    room = Rooms.Room.create(alice, room_identity)

    bob = User.login("Bob")
    bob_key = bob |> Identity.pub_key()
    bob_hash = bob_key |> Utils.hash()

    assert [] = room.requests

    room = room |> Rooms.Room.add_request(bob)

    assert [{bob_hash, bob_key, :pending}] == room.requests

    assert room |> Rooms.Room.is_requested_by?(bob_hash)

    room = room |> Rooms.Room.approve_requests(room_identity)

    assert [{^bob_hash, ^bob_key, {enc_secret, blob}}] = room.requests

    secret =
      enc_secret
      |> User.decrypt(bob)

    decrypted =
      blob
      |> Utils.decrypt_blob(secret)
      |> :erlang.binary_to_term()

    assert room_identity == decrypted

    {room, [joined_identitiy]} = room |> Rooms.Room.join_approved_requests(bob)

    assert room_identity == joined_identitiy
    assert [] = room.requests
  end
end

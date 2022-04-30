defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "room creation" do
    alice = User.login("Alice")
    room_name = "Alice's room"
    room_identity = alice |> Rooms.add(room_name)
    room = Rooms.Room.create(alice, room_identity)

    assert %Rooms.Room{} = room

    correct = ~s|#Chat.Rooms.Room<name: "#{room_name}", ...>|

    assert correct == inspect(room)
  end

  test "room messages" do
    alice = User.login("Alice")
    alice |> User.register()
    alice_hash = alice |> Identity.pub_key() |> Utils.hash()

    room_identity = alice |> Rooms.add("some room")
    room = Rooms.Room.create(alice, room_identity)

    message = "hello, room"
    image = ["image_content", "image/plain"]
    file = ["file content", "plain/text", "file.txt", "10 B"]

    room |> Rooms.add_text(alice, message)
    room |> Rooms.add_memo(alice, message)
    room |> Rooms.add_file(alice, file)
    image_msg = room |> Rooms.add_image(alice, image)

    assert [
             %Rooms.PlainMessage{type: :file},
             %Rooms.PlainMessage{type: :image},
             %Rooms.PlainMessage{type: :memo},
             %Rooms.PlainMessage{content: ^message, type: :text, author_hash: ^alice_hash}
           ] =
             room
             |> Rooms.read(room_identity, &User.id_map_builder/1)
             |> Enum.sort_by(fn %{type: type} -> type end)

    assert %Rooms.PlainMessage{type: :image} = image_msg |> Rooms.read_message(room_identity)
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
      |> Utils.decrypt(bob)

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

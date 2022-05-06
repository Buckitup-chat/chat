defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Card
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
    {_alice, room_identity, room} = alice_and_room()

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

  test "room list should return my created room" do
    alice = User.login("Alice")
    room_name = "Some my room"
    room_identity = alice |> Rooms.add(room_name)
    room_hash = room_identity |> Utils.hash()

    {my_rooms, _other} = Rooms.list([room_identity])

    assert [%Card{name: ^room_name}] = my_rooms

    assert nil == Rooms.get("")
    assert %Rooms.Room{name: ^room_name} = Rooms.get(room_hash)
  end

  test "requesting room should work" do
    alice = User.login("Alice")
    room_name = "Some my room"
    room_identity = alice |> Rooms.add(room_name)
    room_hash = room_identity |> Utils.hash()

    bob = User.login("Bob")

    Rooms.add_request(room_hash, bob)

    assert 1 =
             Rooms.list([])
             |> elem(1)
             |> Enum.filter(&Rooms.is_requested_by?(&1.hash, bob |> Utils.hash()))
             |> Enum.count()

    assert [] = Rooms.join_approved_requests(room_hash, bob)

    Rooms.approve_requests(room_hash, room_identity)

    assert [^room_identity] = Rooms.join_approved_requests(room_hash, bob)
  end

  test "message removed from room should not accessed any more" do
    {alice, room_identity, room} = alice_and_room()
    User.register(alice)

    time = DateTime.utc_now() |> DateTime.add(-10, :second)

    Rooms.add_text(room, alice, "Hello", now: time)
    Rooms.add_text(room, alice, "1", now: time |> DateTime.add(2, :second))
    Rooms.add_text(room, alice, "2", now: time |> DateTime.add(5, :second))

    [msg] =
      Rooms.read(
        room,
        room_identity,
        &User.id_map_builder/1,
        {time |> DateTime.add(5, :second) |> DateTime.to_unix(), 0},
        1
      )

    assert "1" == msg.content

    Rooms.delete_message({msg.timestamp, msg.id}, room_identity, alice)

    assert [_, _] =
             Rooms.read(
               room,
               room_identity,
               &User.id_map_builder/1
             )
  end

  defp alice_and_room do
    alice = User.login("Alice")

    room_identity = alice |> Rooms.add("Alice room")
    room = Rooms.Room.create(alice, room_identity)

    {alice, room_identity, room}
  end
end

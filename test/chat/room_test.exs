defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Db.ChangeTracker
  alias Chat.Identity
  alias Chat.Memo
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias Support.FakeData

  test "room creation" do
    alice = User.login("Alice")
    room_name = "Alice's room"
    room_identity = alice |> Rooms.add(room_name)
    room = Rooms.Room.create(alice, room_identity)

    assert %Rooms.Room{} = room

    correct = ~s|#Chat.Rooms.Room<name: "#{room_name}", type: :public, ...>|

    assert correct == inspect(room)
  end

  test "room messages" do
    alice = User.login("Alice")
    alice |> User.register()
    alice_hash = alice |> Identity.pub_key() |> Utils.hash()

    room_identity = alice |> Rooms.add("some room")
    room = Rooms.Room.create(alice, room_identity)

    message = "hello, room"

    message
    |> Messages.Text.new(1)
    |> Rooms.add_new_message(alice, room.pub_key)

    message
    |> String.pad_trailing(200, "-")
    |> Messages.Text.new(2)
    |> Rooms.add_new_message(alice, room.pub_key)

    FakeData.file()
    |> Map.put(:timestamp, 3)
    |> Rooms.add_new_message(alice, room.pub_key)

    image_msg =
      FakeData.image("2.pp")
      |> Map.put(:timestamp, 4)
      |> Rooms.add_new_message(alice, room.pub_key)

    image_msg
    |> Rooms.await_saved(room.pub_key)

    assert [
             %Rooms.PlainMessage{content: ^message, type: :text, author_hash: ^alice_hash},
             %Rooms.PlainMessage{type: :memo},
             %Rooms.PlainMessage{type: :file},
             %Rooms.PlainMessage{type: :image}
           ] =
             room
             |> Rooms.read(room_identity, &User.id_map_builder/1)

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

    room = room |> Rooms.Room.approve_request(bob_hash, room_identity, [])

    assert [{^bob_hash, ^bob_key, encrypted_identity}] = room.requests

    decrypted_identity = Rooms.decrypt_identity(encrypted_identity, bob)

    assert room_identity == decrypted_identity

    room = room_identity |> Rooms.join_approved_request(bob)

    assert [] = room.requests
  end

  test "room list should return my created room" do
    alice = User.login("Alice")
    room_name = "Some my room"
    room_identity = alice |> Rooms.add(room_name)
    Rooms.await_saved(room_identity)
    room_hash = room_identity |> Utils.hash()

    {my_rooms, _other} = Rooms.list([room_identity])

    assert [%{name: ^room_name}] = my_rooms

    assert nil == Rooms.get("")
    assert %Rooms.Room{name: ^room_name} = Rooms.get(room_hash)
  end

  test "requesting room should work" do
    alice = User.login("Alice")
    room_name = "Some my room"
    room_identity = alice |> Rooms.add(room_name)
    room_hash = room_identity |> Utils.hash()

    bob = User.login("Bob")
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)
    assert Rooms.is_requested_by?(room_hash, bob_hash)

    Rooms.approve_request(room_hash, bob_hash, room_identity)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, {_, _}}]} = Rooms.get(room_hash)
  end

  test "message removed from room should not accessed any more" do
    {alice, room_identity, room} = alice_and_room()
    User.register(alice)

    [
      Messages.Text.new("Hello", 1),
      Messages.Text.new("1", 2),
      Messages.Text.new("2", 3)
    ]
    |> Enum.map(&Rooms.add_new_message(&1, alice, room.pub_key))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
        &User.id_map_builder/1,
        {3, 0},
        1
      )

    assert "1" == msg.content

    Rooms.delete_message({msg.timestamp, msg.id}, room_identity, alice)
    ChangeTracker.await()

    assert [_, _] =
             Rooms.read(
               room,
               room_identity,
               &User.id_map_builder/1
             )
  end

  test "updated message should be stored" do
    {alice, room_identity, room} = alice_and_room()

    User.register(alice)
    |> User.await_saved()

    [
      Messages.Text.new("Hello", 1),
      Messages.Text.new("1", 2),
      Messages.Text.new("2", 3)
    ]
    |> Enum.map(&Rooms.add_new_message(&1, alice, room.pub_key))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
        &User.id_map_builder/1,
        {3, 0},
        1
      )

    assert "1" == msg.content

    "111"
    |> Messages.Text.new(0)
    |> Rooms.update_message({msg.index, msg.id}, alice, room_identity)
    |> Rooms.await_saved(room_identity |> Identity.pub_key())

    assert [_, updated_msg, _] =
             Rooms.read(
               room,
               room_identity,
               &User.id_map_builder/1
             )

    assert "111" = updated_msg.content
  end

  test "updated memo message should be stored" do
    {alice, room_identity, room} = alice_and_room()
    User.register(alice)

    [
      Messages.Text.new("Hello", 1),
      Messages.Text.new("1", 2),
      Messages.Text.new("2", 3)
    ]
    |> Enum.map(&Rooms.add_new_message(&1, alice, room.pub_key))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
        &User.id_map_builder/1,
        {3, 0},
        1
      )

    assert "1" == msg.content

    "111"
    |> String.pad_trailing(200, "-")
    |> Messages.Text.new(0)
    |> Rooms.update_message({msg.index, msg.id}, alice, room_identity)

    assert [_, _, _] =
             Rooms.read(
               room,
               room_identity,
               &User.id_map_builder/1
             )

    assert String.pad_trailing("111", 200, "-") ==
             Rooms.read_message({msg.timestamp, msg.id}, room_identity, &User.id_map_builder/1)
             |> Map.get(:content)
             |> StorageId.from_json()
             |> Memo.get()
  end

  defp alice_and_room do
    alice = User.login("Alice")

    room_identity = alice |> Rooms.add("Alice room")
    room = Rooms.Room.create(alice, room_identity)

    {alice, room_identity, room}
  end
end

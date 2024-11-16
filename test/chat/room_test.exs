defmodule Chat.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Chat.Content.Memo
  alias Chat.Db.ChangeTracker
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Rooms.RoomRequest
  alias Chat.User
  alias Chat.Utils.StorageId
  alias Support.FakeData

  test "room creation" do
    alice = User.login("Alice")
    room_name = "Alice's room"
    {_room_identity, room} = alice |> Rooms.add(room_name)

    assert %Rooms.Room{} = room

    correct = ~s|#Chat.Rooms.Room<name: "#{room_name}", type: :public, ...>|

    assert correct == inspect(room)
  end

  test "room messages" do
    alice = User.login("Alice")
    alice |> User.register()
    alice_key = alice |> Identity.pub_key()

    {room_identity, room} = alice |> Rooms.add("some room")

    message = "hello, room"

    message
    |> Messages.Text.new(1)
    |> Rooms.add_new_message(alice, room_identity)

    message
    |> String.pad_trailing(200, "-")
    |> Messages.Text.new(2)
    |> Rooms.add_new_message(alice, room_identity)

    FakeData.file()
    |> Map.put(:timestamp, 3)
    |> Rooms.add_new_message(alice, room_identity)

    image_msg =
      FakeData.image("2.pp")
      |> Map.put(:timestamp, 4)
      |> Rooms.add_new_message(alice, room_identity)

    image_msg
    |> Rooms.await_saved(room.pub_key)

    assert [
             %Rooms.PlainMessage{content: ^message, type: :text, author_key: ^alice_key},
             %Rooms.PlainMessage{type: :memo},
             %Rooms.PlainMessage{type: :audio},
             %Rooms.PlainMessage{type: :image}
           ] =
             room
             |> Rooms.read(room_identity)

    assert %Rooms.PlainMessage{type: :image} = image_msg |> Rooms.read_message(room_identity)
  end

  test "room invite" do
    {_alice, room_identity, room} = alice_and_room()

    refute is_nil(room_identity)

    bob = User.login("Bob")
    bob_key = bob |> Identity.pub_key()

    assert [] = room.requests

    room = room |> Rooms.Room.add_request(bob)

    assert [%{requester_key: ^bob_key, pending?: true}] = room.requests

    assert room |> Rooms.Room.requested_by?(bob_key)

    room = room |> Rooms.Room.approve_request(bob_key, room_identity, [])

    assert [
             %RoomRequest{
               requester_key: ^bob_key,
               pending?: false,
               ciphered_room_identity: encrypted_identity
             }
           ] = room.requests

    decrypted_identity = Rooms.decipher_identity_with_key(encrypted_identity, bob, room.pub_key)

    assert room_identity == %{decrypted_identity | name: room_identity.name}

    ChangeTracker.await()

    refute is_nil(room_identity)

    room = room_identity |> Rooms.clear_approved_request(bob)

    assert [] = room.requests
  end

  # todo: create test
  test "room invite removal", do: :todo

  test "room list should return my created room" do
    alice = User.login("Alice")
    room_name = "Some my room"
    {room_identity, _room} = alice |> Rooms.add(room_name)
    Rooms.await_saved(room_identity)
    room_key = room_identity |> Identity.pub_key()

    {my_rooms, _other} = Rooms.list(%{room_key => room_identity})

    assert [%{name: ^room_name}] = my_rooms

    assert nil == Rooms.get("")
    assert %Rooms.Room{name: ^room_name} = Rooms.get(room_key)
  end

  test "requesting room should work" do
    alice = User.login("Alice")
    room_name = "Some my room"
    {room_identity, _room} = alice |> Rooms.add(room_name)
    room_key = room_identity |> Identity.pub_key()

    bob = User.login("Bob")
    bob_pub_key = bob |> Identity.pub_key()
    ChangeTracker.await()

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: true}]} =
             Rooms.get(room_key)

    assert Rooms.requested_by?(room_key, bob_pub_key)

    Rooms.approve_request(room_key, bob_pub_key, room_identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: false}]} =
             Rooms.get(room_key)
  end

  test "message removed from room should not accessed any more" do
    {alice, room_identity, room} = alice_and_room()
    User.register(alice)

    [
      Messages.Text.new("Hello", 1),
      Messages.Text.new("1", 2),
      Messages.Text.new("2", 3)
    ]
    |> Enum.map(&Rooms.add_new_message(&1, alice, room_identity))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
        {3, 0},
        1
      )

    assert "1" == msg.content

    Rooms.delete_message({msg.timestamp, msg.id}, room_identity, alice)
    ChangeTracker.await()

    assert [_, _] =
             Rooms.read(
               room,
               room_identity
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
    |> Enum.map(&Rooms.add_new_message(&1, alice, room_identity))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
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
               room_identity
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
    |> Enum.map(&Rooms.add_new_message(&1, alice, room_identity))
    |> List.last()
    |> Rooms.await_saved(room.pub_key)

    [msg] =
      Rooms.read(
        room,
        room_identity,
        {3, 0},
        1
      )

    assert "1" == msg.content

    "111"
    |> String.pad_trailing(200, "-")
    |> Messages.Text.new(0)
    |> Rooms.update_message({msg.index, msg.id}, alice, room_identity)
    |> Rooms.await_saved(room.pub_key)

    assert [_, _, _] =
             Rooms.read(
               room,
               room_identity
             )

    assert String.pad_trailing("111", 200, "-") ==
             Rooms.read_message({msg.timestamp, msg.id}, room_identity)
             |> Map.get(:content)
             |> StorageId.from_json()
             |> Memo.get()
  end

  test "room hash" do
    {_alice, room_identity, room} = alice_and_room()

    assert room_identity |> Enigma.hash() == room |> Enigma.hash()
    assert room_identity.public_key |> Enigma.hash() == room |> Enigma.hash()
  end

  defp alice_and_room do
    alice = User.login("Alice")

    {room_identity, room} = alice |> Rooms.add("Alice room")

    {alice, room_identity, room}
  end
end

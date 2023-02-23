defmodule Chat.Rooms.PrivateRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.Content.RoomInvites
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils.StorageId

  test "should create as usual" do
    {_alice, _identity, room} = "Alice" |> make_user_and_private_room()

    assert %Rooms.Room{type: :private} = room
  end

  test "should not be seen in list" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_key = identity |> Identity.pub_key()

    {_, list} = Rooms.list(%{})

    refute list |> Enum.any?(&(&1.pub_key == room_key))
  end

  test "should be seen in list when i have a key" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_key = identity |> Identity.pub_key()

    {list, _} = Rooms.list(%{room_key => identity})

    assert list |> Enum.any?(&(&1.pub_key == room_key))
  end

  test "adding request and approving requests should do nothing" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()

    Rooms.add_request(room_key, bob, 0)
    assert %Rooms.Room{requests: []} = Rooms.get(room_key)

    Rooms.approve_request(room_key, bob |> Identity.pub_key(), identity)
    assert %Rooms.Room{requests: []} = Rooms.get(room_key)
  end

  test "should be joinable by getting a room key message in dialog" do
    {alice, identity, _room} = "Alice" |> make_user_and_private_room()
    bob = "Bob" |> User.login()
    bob_key = User.register(bob)
    User.await_saved(bob_key)
    bob_card = User.by_id(bob_key)

    dialog = Dialogs.find_or_open(alice, bob_card)

    identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_message] = dialog |> Dialogs.read(bob)
    assert :room_invite == bob_message.type

    bob_room_identity =
      bob_message.content
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    assert bob_room_identity == identity
  end

  test "what else ?", do: :todo

  def make_user_and_private_room(name) do
    alice = User.login(name)
    {room_identity, _room} = Rooms.add(alice, "#{name}'s Private room", :private)
    ChangeTracker.await({:rooms, room_identity.public_key})
    room = Rooms.get(room_identity.public_key)

    {alice, room_identity, room}
  end
end

defmodule Chat.Rooms.PrivateRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.RoomInvites
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "should create as usual" do
    {_alice, _identity, room} = "Alice" |> make_user_and_private_room()

    assert %Rooms.Room{type: :private} = room
  end

  test "should not be seen in list" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_hash = identity |> Utils.hash()

    {_, list} = Rooms.list([])

    refute list |> Enum.any?(&(&1.hash == room_hash))
  end

  test "should be seen in list when i have a key" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_hash = identity |> Utils.hash()

    {list, _} = Rooms.list([identity])

    assert list |> Enum.any?(&(&1.hash == room_hash))
  end

  test "adding request and approving requests should do nothing" do
    {_alice, identity, _room} = "Alice" |> make_user_and_private_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()

    Rooms.add_request(room_hash, bob, 0)
    assert %Rooms.Room{requests: []} = Rooms.get(room_hash)

    Rooms.approve_requests(room_hash, identity)
    assert %Rooms.Room{requests: []} = Rooms.get(room_hash)
  end

  test "should be joinable by getting a room key message in dialog" do
    {alice, identity, _room} = "Alice" |> make_user_and_private_room()
    bob = "Bob" |> User.login()
    bob_hash = User.register(bob)
    bob_card = User.by_id(bob_hash)

    dialog = Dialogs.find_or_open(alice, bob_card)

    identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(alice, dialog)

    [bob_message] = dialog |> Dialogs.read(bob)
    assert :room_invite == bob_message.type

    bob_room_identity =
      bob_message.content
      |> Utils.StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    assert bob_room_identity == identity
  end

  test "what else ?", do: :todo

  def make_user_and_private_room(name) do
    alice = User.login(name)
    room_identity = Rooms.add(alice, "#{name}'s Private room", :private)
    room = Rooms.get(room_identity |> Utils.hash())

    {alice, room_identity, room}
  end
end

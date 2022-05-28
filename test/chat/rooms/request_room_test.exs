defmodule Chat.Rooms.RequestRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "should create as usual" do
    {_alice, _identity, room} = "Alice" |> user_and_request_room()

    assert %Rooms.Room{type: :request} = room
  end

  test "should be seen in list" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()

    {_, room_list} = Rooms.list([])

    assert nil != room_list |> Enum.find_value(&(&1.hash == room_hash))
  end

  test "requesting should work as for public" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob)
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)

    Rooms.approve_requests(room_hash, identity)
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)
  end

  test "should be approved individually by any room key holder" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob)
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity)

    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, _bob_room_key}]} =
             Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity)

    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, _bob_room_key}]} =
             Rooms.get(room_hash)

    assert [^identity] = Rooms.join_approved_requests(room_hash, bob)
  end

  test "should show a list of pending user requests" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob)

    assert [{^bob_hash, ^bob_pub_key}] = Rooms.list_pending_requests(room_hash)
    Rooms.approve_request(room_hash, bob_hash, identity)

    assert [] = Rooms.list_pending_requests(room_hash)
  end

  test "reuest message should be added upon requesting" do
    {_alice, identity, room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    User.register(bob)

    Rooms.add_request(room_hash, bob)

    messages = Rooms.read(room, identity, &User.id_map_builder/1)

    assert [%{type: :request}] = messages
  end

  defp user_and_request_room(name) do
    alice = User.login(name)
    room_identity = Rooms.add(alice, "#{name}'s Request room", :request)
    room = Rooms.get(room_identity |> Utils.hash())

    {alice, room_identity, room}
  end
end

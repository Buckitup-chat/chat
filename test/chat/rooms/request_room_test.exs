defmodule Chat.Rooms.RequestRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Db.ChangeTracker
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

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, {_, _}}]} = Rooms.get(room_hash)
  end

  test "should be approved individually by any room key holder" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, _bob_room_key}]} =
             Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, _bob_room_key}]} =
             Rooms.get(room_hash)

    assert %Rooms.Room{requests: []} = Rooms.join_approved_request(identity, bob)
  end

  test "should NOT be approved individually when flag public_only is applied" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)

    Rooms.approve_request(room_hash, bob_hash, identity, public_only: true)
    ChangeTracker.await()
    assert %Rooms.Room{requests: [{^bob_hash, ^bob_pub_key, :pending}]} = Rooms.get(room_hash)
  end

  test "should show a list of pending user requests" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()
    bob_hash = bob |> Utils.hash()

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()

    assert [{^bob_hash, ^bob_pub_key}] = Rooms.list_pending_requests(room_hash)
    Rooms.approve_request(room_hash, bob_hash, identity)
    ChangeTracker.await()

    assert [] = Rooms.list_pending_requests(room_hash)
  end

  test "reuest message should be added upon requesting" do
    {_alice, identity, room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()
    User.register(bob)

    Rooms.add_request(room_hash, bob, 0)
    ChangeTracker.await()

    messages = Rooms.read(room, identity, &User.id_map_builder/1)

    assert [%{type: :request}] = messages
  end

  defp user_and_request_room(name) do
    alice = User.login(name)
    {room_identity, _room} = Rooms.add(alice, "#{name}'s Request room", :request)
    Rooms.await_saved(room_identity)
    room = Rooms.get(room_identity |> Utils.hash())

    {alice, room_identity, room}
  end
end

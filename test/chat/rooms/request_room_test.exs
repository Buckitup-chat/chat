defmodule Chat.Rooms.RequestRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Db.ChangeTracker
  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User

  test "should create as usual" do
    {_alice, _identity, room} = "Alice" |> user_and_request_room()

    assert %Rooms.Room{type: :request} = room
  end

  test "should be seen in list" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()

    {_, room_list} = Rooms.list(%{})

    assert nil != room_list |> Enum.find_value(&(&1.pub_key == room_key))
  end

  test "requesting should work as for public" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: true}]} =
             Rooms.get(room_key)

    Rooms.approve_request(room_key, bob_pub_key, identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: false}]} =
             Rooms.get(room_key)
  end

  test "should be approved individually by any room key holder" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: true}]} =
             Rooms.get(room_key)

    Rooms.approve_request(room_key, bob_pub_key, identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: false}]} =
             Rooms.get(room_key)

    Rooms.approve_request(room_key, bob_pub_key, identity)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: false}]} =
             Rooms.get(room_key)

    assert %Rooms.Room{requests: []} = Rooms.clear_approved_request(identity, bob)
  end

  test "should NOT be approved individually when flag public_only is applied" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: true}]} =
             Rooms.get(room_key)

    Rooms.approve_request(room_key, bob_pub_key, identity, public_only: true)
    ChangeTracker.await()

    assert %Rooms.Room{requests: [%{requester_key: ^bob_pub_key, pending?: true}]} =
             Rooms.get(room_key)
  end

  test "should show a list of pending user requests" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()
    bob_pub_key = bob |> Identity.pub_key()

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    assert [%{requester_key: ^bob_pub_key, pending?: true}] =
             Rooms.list_pending_requests(room_key)

    Rooms.approve_request(room_key, bob_pub_key, identity)
    ChangeTracker.await()

    assert [] = Rooms.list_pending_requests(room_key)
  end

  test "request message should be added upon requesting" do
    {_alice, identity, room} = "Alice" |> user_and_request_room()
    room_key = identity |> Identity.pub_key()
    bob = "Bob" |> User.login()
    User.register(bob)

    Rooms.add_request(room_key, bob, 0)
    ChangeTracker.await()

    messages = Rooms.read(room, identity)

    assert [%{type: :request}] = messages
  end

  defp user_and_request_room(name) do
    alice = User.login(name)
    {room_identity, _room} = Rooms.add(alice, "#{name}'s Request room", :request)
    ChangeTracker.await()
    room = Rooms.get(room_identity |> Identity.pub_key())

    {alice, room_identity, room}
  end
end

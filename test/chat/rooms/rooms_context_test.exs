defmodule Chat.Rooms.RoomsContextTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Db.ChangeTracker
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Rooms.Room
  alias Chat.Rooms.RoomRequest
  alias Chat.SignedParcel
  alias Chat.User

  describe "message navigation" do
    setup do
      alice = User.login("Alice")
      {room_identity, room} = alice |> Rooms.add("navigation room")

      [first, second] =
        ["first", "second"]
        |> Enum.with_index(1)
        |> Enum.map(fn {text, ts} ->
          text
          |> Messages.Text.new(ts)
          |> Rooms.add_new_message(alice, room_identity)
          |> tap(&Rooms.await_saved(&1, room.pub_key))
        end)

      %{room_identity: room_identity, room: room, first: first, second: second}
    end

    test "reads the previous and the next message", context do
      %{room_identity: identity, first: {first_index, first_msg}} = context
      %{second: {second_index, second_msg}} = context
      any = fn _ -> true end

      assert %Rooms.PlainMessage{content: "first"} =
               Rooms.read_prev_message({second_index, second_msg.id}, identity, any)

      assert %Rooms.PlainMessage{content: "second"} =
               Rooms.read_next_message({first_index, first_msg.id}, identity, any)

      assert nil == Rooms.read_prev_message({first_index, first_msg.id}, identity, any)
      assert nil == Rooms.read_next_message({second_index, second_msg.id}, identity, any)
    end

    test "reads a range of messages", %{room_identity: identity, room: room} do
      assert [%{content: "first"}, %{content: "second"}] =
               Rooms.read_to(room, identity) |> Enum.sort_by(& &1.timestamp)
    end

    test "delete removes the room and its messages", %{room_identity: identity, room: room} do
      Rooms.delete(room.pub_key)
      ChangeTracker.await()

      assert nil == Rooms.get(room.pub_key)
      assert [] == Rooms.read(room, identity)
    end
  end

  describe "requests" do
    setup do
      alice = User.login("Alice")
      bob = User.login("Bob")
      {room_identity, room} = alice |> Rooms.add("request room", :request)
      Rooms.await_saved(room_identity)

      %{room_identity: room_identity, room: room, bob: bob, bob_key: Identity.pub_key(bob)}
    end

    test "get_request finds the user request", %{room: room, bob: bob, bob_key: bob_key} do
      room = room |> Room.add_request(bob)

      assert %RoomRequest{requester_key: ^bob_key, pending?: true} =
               Rooms.get_request(room, bob_key)

      assert nil == Rooms.get_request(room, Identity.pub_key(User.login("Carol")))
    end

    test "approves a room struct with an already ciphered identity", context do
      %{room: room, bob_key: bob_key} = context
      room = room |> Room.add_request(bob_key)

      assert %Room{requests: [%{pending?: false, ciphered_room_identity: "ciphered"}]} =
               Rooms.approve_request(room, bob_key, "ciphered")
    end

    test "lists approved requests by room key", context do
      %{room: room, bob_key: bob_key} = context
      request_and_approve(context)

      assert [%RoomRequest{requester_key: ^bob_key}] =
               Rooms.list_approved_requests_for(room.pub_key, bob_key)

      assert [] ==
               Rooms.list_approved_requests_for(Identity.pub_key(Identity.create("x")), bob_key)
    end

    test "clears an approved request by room public key", context do
      %{room: room, bob_key: bob_key} = context
      request_and_approve(context)

      Rooms.clear_approved_request(room.pub_key, bob_key)
      ChangeTracker.await()

      assert [] == Rooms.list_approved_requests_for(room.pub_key, bob_key)
    end
  end

  defp request_and_approve(%{room: room, room_identity: identity, bob: bob, bob_key: bob_key}) do
    Rooms.add_request(room.pub_key, bob, 0)
    ChangeTracker.await()
    Rooms.approve_request(room.pub_key, bob_key, identity)
    ChangeTracker.await()
  end

  describe "private room" do
    setup do
      alice = User.login("Alice")
      {room_identity, room} = alice |> Rooms.add("private room", :private)

      %{room_identity: room_identity, room: room, bob_key: Identity.pub_key(User.login("Bob"))}
    end

    test "ignores requests", %{room: room, room_identity: room_identity, bob_key: bob_key} do
      assert room == Room.add_request(room, bob_key)
      assert [] == Room.list_pending_requests(%{room | requests: [RoomRequest.new(bob_key)]})
      assert room == Room.approve_request(room, bob_key, room_identity, [])
      assert room == Room.clear_approved_request(room, bob_key)
    end
  end

  describe "parcel_to_indexed_message" do
    setup do
      alice = User.login("Alice")
      {room_identity, _room} = alice |> Rooms.add("parcel room")

      parcel =
        "in parcel"
        |> Messages.Text.new(1)
        |> SignedParcel.wrap_room_message(room_identity, alice, index: 3)

      %{parcel: parcel, room_identity: room_identity}
    end

    test "extracts the message with or without a room check", context do
      %{parcel: parcel, room_identity: room_identity} = context

      assert {3, %Rooms.Message{type: :text}} = Rooms.parcel_to_indexed_message(parcel)

      assert {3, %Rooms.Message{}} = Rooms.parcel_to_indexed_message(parcel, room_identity)
    end

    test "raises for a parcel of another room", %{parcel: parcel} do
      assert_raise ArgumentError, "Parcel does not contain a room message for this room", fn ->
        Rooms.parcel_to_indexed_message(parcel, Identity.create("other room"))
      end
    end

    test "raises for a parcel without a room message" do
      assert_raise ArgumentError, "Parcel does not contain a room message", fn ->
        Rooms.parcel_to_indexed_message(%SignedParcel{})
      end
    end
  end
end

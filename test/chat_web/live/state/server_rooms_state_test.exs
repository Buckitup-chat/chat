defmodule ChatWeb.State.ServerRoomsStateTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias Chat.Rooms.Room
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState
  alias ChatWeb.State.ServerRoomsState
  alias Phoenix.LiveView.Socket

  setup do
    me = Identity.create("Alice")
    joined = Identity.create("Joined secret")

    rooms = %{
      joined: Room.create(me, joined, :private),
      public: Room.create(me, Identity.create("Bravo public"), :public),
      request: Room.create(me, Identity.create("Alpha request"), :request),
      private: Room.create(me, Identity.create("Hidden private"), :private)
    }

    socket =
      %Socket{}
      |> ActorState.set(Actor.new(me, [joined]))
      |> RoomMapState.derive()
      |> ServerRoomsState.set(Map.values(rooms))

    [me: me, rooms: rooms, socket: socket]
  end

  test "get/1 defaults to an empty list" do
    assert [] == ServerRoomsState.get(%Socket{})
    refute ServerRoomsState.has_room?(%Socket{}, "any key")
  end

  test "insert_room/2 prepends to the stored rooms", %{rooms: rooms} do
    socket =
      %Socket{}
      |> ServerRoomsState.insert_room(rooms.public)
      |> ServerRoomsState.insert_room(rooms.request)

    assert [rooms.request, rooms.public] == ServerRoomsState.get(socket)
    assert ServerRoomsState.has_room?(socket, rooms.public.pub_key)
    refute ServerRoomsState.has_room?(socket, rooms.private.pub_key)
  end

  test "get_room_lists/2 splits visible rooms into joined and new, sorted by name", ctx do
    %{joined: joined, public: public, request: request} = ctx.rooms

    assert {[^joined], [new_request, new_public]} =
             ServerRoomsState.get_room_lists(ctx.socket, "")

    assert new_request.pub_key == request.pub_key
    assert new_public.pub_key == public.pub_key
    refute new_request.is_requested?
    refute new_public.is_requested?
  end

  test "get_room_lists/2 filters by a case-insensitive search term", %{socket: socket} do
    assert {[], [%{name: "Bravo public"}]} = ServerRoomsState.get_room_lists(socket, "BRAVO")
    assert {[%{name: "Joined secret"}], []} = ServerRoomsState.get_room_lists(socket, "secret")
  end

  test "mark_as_requested/2 records my request on that room only", ctx do
    socket = ServerRoomsState.mark_as_requested(ctx.socket, ctx.rooms.request.pub_key)

    {_joined, new} = ServerRoomsState.get_room_lists(socket, "")

    assert [%{name: "Alpha request", is_requested?: true}, %{is_requested?: false}] = new
  end
end

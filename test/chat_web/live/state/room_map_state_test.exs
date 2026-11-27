defmodule ChatWeb.State.RoomMapStateTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState
  alias Phoenix.LiveView.Socket

  test "get/1 defaults to an empty map before derive/1" do
    assert %{} == RoomMapState.get(%Socket{})
    refute RoomMapState.has_room?(%Socket{}, "any key")
  end

  test "derive/1 maps the actor's room identities by public key" do
    room = Identity.create("Lobby")
    room_key = Identity.pub_key(room)

    socket =
      %Socket{}
      |> ActorState.set(Actor.new(Identity.create("Alice"), [room]))
      |> RoomMapState.derive()

    assert %{^room_key => ^room} = RoomMapState.get(socket)
    assert RoomMapState.has_room?(socket, room_key)
    refute RoomMapState.has_room?(socket, Identity.create("Other") |> Identity.pub_key())
  end
end

defmodule ChatWeb.State.ActorStateTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias ChatWeb.State.ActorState
  alias Phoenix.LiveView.Socket

  setup do
    me = Identity.create("Alice")
    room = Identity.create("Lobby")

    [me: me, room: room, socket: ActorState.set(%Socket{}, Actor.new(me, []))]
  end

  test "get/1 defaults to an empty map before an actor is set" do
    assert %{} == ActorState.get(%Socket{})
  end

  test "set/2 stores the actor for get/1", %{me: me, socket: socket} do
    assert %Actor{me: ^me, rooms: []} = ActorState.get(socket)
  end

  test "my_identity/1 and my_pub_key/1 read the actor's own identity", ctx do
    assert ctx.me == ActorState.my_identity(ctx.socket)
    assert Identity.pub_key(ctx.me) == ActorState.my_pub_key(ctx.socket)
  end

  test "add_room_identity/2 prepends the room to the actor's rooms", ctx do
    other = Identity.create("Other")

    socket =
      ctx.socket
      |> ActorState.add_room_identity(ctx.room)
      |> ActorState.add_room_identity(other)

    assert [^other, room] = ActorState.get(socket).rooms
    assert room == ctx.room
  end
end

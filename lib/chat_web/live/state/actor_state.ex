defmodule ChatWeb.State.ActorState do
  @moduledoc "Actor state in socket private field"
  import Tools.SocketPrivate

  alias Chat.Proto.Identify

  def set(socket, %Chat.Actor{} = actor), do: set_private(socket, :actor, actor)
  def get(socket), do: socket |> get_private(:actor, %{})

  def my_identity(socket) do
    socket
    |> get_private(:actor)
    |> Map.get(:me)
  end

  def my_pub_key(socket) do
    socket
    |> my_identity()
    |> Identify.pub_key()
  end

  def add_room_identity(socket, room_identity) do
    update_private(
      socket,
      :actor,
      fn actor ->
        Map.put(actor, :rooms, [room_identity | actor.rooms])
      end,
      nil
    )
  end
end

defmodule ChatWeb.State.RoomMapState do
  @moduledoc "RoomMap state in socket private field"

  import Tools.SocketPrivate

  alias Chat.Proto.Identify
  alias ChatWeb.State.ActorState

  def get(socket) do
    socket
    |> get_private(:room_map, %{})
  end

  def has_room?(socket, room_key) do
    socket
    |> get()
    |> Map.has_key?(room_key)
  end

  def derive(socket) do
    actor = socket |> ActorState.get()

    socket
    |> set_private(:room_map, Map.new(actor.rooms, &{&1 |> Identify.pub_key(), &1}))
  end
end

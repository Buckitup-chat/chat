defmodule ChatWeb.State.ServerRoomsState do
  @moduledoc "ServerRooms state in socket private field"
  import Tools.SocketPrivate

  alias Chat.Rooms.Room
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState

  def get(socket) do
    socket
    |> get_private(:server_rooms, [])
  end

  def set(socket, server_rooms), do: set_private(socket, :server_rooms, server_rooms)

  def insert_room(socket, room) do
    socket
    |> update_private(:server_rooms, &[room | &1], [])
  end

  def has_room?(socket, room_key) do
    Enum.any?(socket |> get(), &(&1.pub_key == room_key))
  end

  def mark_as_requested(socket, room_key) do
    my_pubkey = ActorState.my_pub_key(socket)

    socket
    |> update_private(
      :server_rooms,
      &Enum.map(&1, fn room ->
        if room.pub_key == room_key,
          do: room |> Room.add_request(my_pubkey),
          else: room
      end),
      []
    )
  end

  def get_room_lists(socket, search_term) do
    my_pubkey = ActorState.my_pub_key(socket)

    {joined, new} =
      socket
      |> get()
      |> Enum.filter(fn room ->
        (room.type in [:public, :request] or RoomMapState.has_room?(socket, room.pub_key)) and
          (search_term == "" or String.match?(room.name, ~r/#{search_term}/i))
      end)
      |> Enum.sort_by(fn room -> room.name end)
      |> Enum.split_with(&RoomMapState.has_room?(socket, &1.pub_key))

    {joined, new |> enrich_with_requested(my_pubkey)}
  end

  defp enrich_with_requested(rooms, my_pubkey) do
    Enum.map(rooms, fn room ->
      Map.put(room, :is_requested?, Room.requested_by?(room, my_pubkey))
    end)
  end
end

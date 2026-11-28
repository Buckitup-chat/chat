defmodule ChatWeb.MainLive.Page.Lobby.RoomRequests do
  @moduledoc """
  Room access requests from the lobby: requesting a room, approving a request (one or
  all pending ones), and joining a room whose request was approved.

  Part of the `ChatWeb.MainLive.Page.Lobby` namespace.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.Broadcast
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Rooms.RoomRequest
  alias ChatWeb.MainLive.Page

  def request_room(
        %{assigns: %{me: me, monotonic_offset: time_offset, new_rooms: rooms}} = socket,
        room_key
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    room =
      Rooms.add_request(room_key, me, time, fn req_message ->
        Page.Room.broadcast_new_message(req_message, room_key, me, time)
      end)

    Rooms.RoomsBroker.put(room)

    Log.request_room_key(me, time, room.pub_key)

    Broadcast.room_requested(room, me |> Identity.pub_key())

    socket
    |> assign(
      :new_rooms,
      Enum.map(rooms, fn
        %{pub_key: pub_key} when pub_key == room.pub_key -> Map.put(room, :is_requested?, true)
        other_room -> other_room
      end)
    )
  end

  def approve_room_request(
        %{assigns: %{room_map: room_map, me: me, monotonic_offset: time_offset}} = socket,
        room_or_hash,
        user_key
      ) do
    room =
      case room_or_hash do
        %Rooms.Room{} = room ->
          Rooms.approve_request(room, user_key, room_map[room.pub_key], public_only: true)

        room_hash ->
          room_key = room_hash |> Base.decode16!(case: :lower)
          Rooms.approve_request(room_key, user_key, room_map[room_key], public_only: true)
      end

    case Rooms.get_request(room, user_key) do
      %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
        time = Chat.Time.monotonic_to_unix(time_offset)
        Log.approve_room_request(me, time, room.pub_key)

        Broadcast.room_request_approved(user_key, room.pub_key, ciphered)

      _ ->
        :ok
    end

    socket
  rescue
    _ -> socket
  end

  def join_approved_room(
        %{assigns: %{me: me, my_id: my_id, monotonic_offset: time_offset, room_map: room_map}} =
          socket,
        ciphered_room_identity,
        user_key,
        room_key
      )
      when my_id == user_key do
    if Map.has_key?(room_map, room_key) do
      socket
    else
      new_room_identity = Rooms.decipher_identity_with_key(ciphered_room_identity, me, room_key)

      time = Chat.Time.monotonic_to_unix(time_offset)
      Rooms.clear_approved_request(new_room_identity, me)
      Log.got_room_key(me, time, new_room_identity |> Identity.pub_key())

      socket
      |> Page.Room.store_new(new_room_identity)
    end
  end

  def join_approved_room(socket, _, _, _), do: socket

  def approve_pending_requests(socket) do
    %{room_map: room_map, me: me, monotonic_offset: time_offset} = socket.assigns

    for room_key <- Map.keys(room_map),
        %RoomRequest{requester_key: user_key} <- Rooms.list_pending_requests(room_key),
        room = Rooms.approve_request(room_key, user_key, room_map[room_key], public_only: true) do
      Rooms.RoomsBroker.put(room)

      case Rooms.get_request(room, user_key) do
        %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
          time = Chat.Time.monotonic_to_unix(time_offset)
          Log.approve_room_request(me, time, room.pub_key)
          Broadcast.room_request_approved(user_key, room.pub_key, ciphered)

        _ ->
          :ok
      end
    end
  rescue
    _ -> :skip
  end

  def join_approved_requests(socket) do
    %{new_rooms: rooms, my_id: my_id} = socket.assigns
    root_pid = socket.root_pid

    for %Rooms.Room{} = room <- rooms,
        request <- Rooms.list_approved_requests_for(room, my_id),
        ciphered = request.ciphered_room_identity,
        true == is_bitstring(ciphered) do
      send(root_pid, {:room_request_approved, ciphered, my_id, room.pub_key})
    end
  rescue
    _ -> :skip
  end
end

defmodule ChatWeb.ProxyLive.Page.Lobby.RoomRequests do
  @moduledoc """
  Proxy lobby room requests: requesting access to a server room, approving requests for
  public rooms we hold, and joining rooms whose request was approved for us.

  Used by `ChatWeb.ProxyLive.Page.Lobby` (events and socket client messages) and
  `ChatWeb.ProxyLive.Page.Lobby.Rooms` (joining approved requests after a room list update).
  """

  import Tools.SocketPrivate

  alias Chat.Proto
  alias Chat.Rooms
  alias ChatWeb.ProxyLive.Page
  alias ChatWeb.ProxyLive.Page.Lobby.Rooms, as: RoomList
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState
  alias ChatWeb.State.ServerRoomsState

  def send_room_request(socket, %{"room" => room_key_raw}) do
    room_key = room_key_raw |> Base.decode16!(case: :lower)

    if not RoomMapState.has_room?(socket, room_key) and
         ServerRoomsState.has_room?(socket, room_key) do
      server = socket |> get_private(:server)
      my_identity = ActorState.my_identity(socket)

      Task.start(fn -> Proxy.request_room(server, my_identity, room_key) end)
    end

    socket
    |> ServerRoomsState.mark_as_requested(room_key)
    |> RoomList.assign_room_list()
  end

  def maybe_approve_room_requested(socket, room, user_key) do
    room_key = room |> Proto.Identify.pub_key()
    room_identity = socket.assigns.room_map[room_key]

    room_is_valid_for_approval? =
      room_identity &&
        room.type == :public &&
        Rooms.Room.valid?(room)

    if room_is_valid_for_approval? do
      server = socket |> get_private(:server)
      my_identity = ActorState.my_identity(socket)

      ciphered_room_identity =
        room_identity
        |> Chat.Identity.to_strings()
        |> Enigma.encrypt(room_identity.private_key, user_key)

      Proxy.approve_room_request(
        server,
        my_identity,
        {room_key, user_key, ciphered_room_identity}
      )

      Chat.Broadcast.room_request_approved(user_key, room_key, ciphered_room_identity)
    end

    socket
  rescue
    _ -> socket
  end

  def join_approved_room(socket, ciphered_room_identity, room_key, user_key) do
    my_identity = ActorState.my_identity(socket)
    my_public_key = ActorState.my_pub_key(socket)
    server = socket |> get_private(:server)

    Task.start(fn ->
      Proxy.clean_room_request(server, my_identity, room_key)
    end)

    cond do
      my_public_key != user_key ->
        socket

      RoomMapState.has_room?(socket, room_key) ->
        socket

      true ->
        new_room_identity =
          Rooms.decipher_identity_with_key(ciphered_room_identity, my_identity, room_key)

        new_room_pub_key = new_room_identity.private_key |> Enigma.private_to_public()

        if new_room_pub_key == room_key and new_room_pub_key == new_room_identity.public_key,
          do: socket |> Page.Room.store_new(new_room_identity),
          else: socket
    end
  end

  def join_approved_requests(socket) do
    new_rooms = socket.assigns.new_rooms
    my_pub_key = ActorState.my_pub_key(socket)

    new_rooms
    |> Enum.reduce(%{}, fn room, acc ->
      Rooms.list_approved_requests_for(room, my_pub_key)
      |> case do
        [] -> acc
        [request | _] -> Map.put(acc, room, request)
      end
    end)
    |> Enum.reduce(socket, fn {room, request}, socket ->
      socket
      |> join_approved_room(request.ciphered_room_identity, room.pub_key, my_pub_key)
    end)
  end
end

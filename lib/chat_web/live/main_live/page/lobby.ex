defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.Component, only: [assign: 3]
  require Logger

  alias Chat.Db.ChangeTracker
  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Db.StatusPoller
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Rooms.RoomRequest
  alias Chat.User
  alias ChatWeb.MainLive.Page

  @topic "chat::lobby"

  def init(socket) do
    PubSub.subscribe(Chat.PubSub, @topic)
    PubSub.subscribe(Chat.PubSub, StatusPoller.channel())

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign(:image_gallery, nil)
    |> assign(:version, get_version())
    |> assign(:db_status, StatusPoller.info())
    |> assign_user_list()
    |> assign_room_list()
    |> assign_admin()
    |> process(&approve_pending_requests/1)
    |> process(&join_approved_requests/1)
  end

  def new_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, name, type)
      when type in [:public, :request, :private] do
    {new_room_identity, new_room} = Rooms.add(me, name, type)
    new_room_card = Chat.Card.from_identity(new_room_identity)

    me |> Log.create_room(Chat.Time.monotonic_to_unix(time_offset), new_room_identity, type)

    ChangeTracker.on_saved(fn ->
      PubSub.broadcast!(Chat.PubSub, @topic, {:new_room, new_room_card})
    end)

    socket
    |> Page.Dialog.store_room_key_copy(new_room_identity)
    |> Page.Login.store_new_room(new_room_identity)
    |> assign_room_list()
    |> Page.Room.init({new_room_identity, new_room})
  end

  def notify_new_user(socket, user_card) do
    ChangeTracker.on_saved(fn ->
      PubSub.broadcast!(
        Chat.PubSub,
        @topic,
        {:new_user, user_card}
      )
    end)

    socket
  end

  def show_new_user(socket, _user_card) do
    socket
    |> assign_user_list()
  end

  def show_new_room(socket, _room_card) do
    socket
    |> assign_room_list()
  end

  def switch_lobby_mode(socket, mode) do
    socket
    |> close_current_mode()
    |> assign(:lobby_mode, String.to_existing_atom(mode))
    |> init_new_mode()
  end

  def request_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, room_key) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    room = Rooms.add_request(room_key, me, time)
    Log.request_room_key(me, time, room.pub_key)

    PubSub.broadcast!(
      Chat.PubSub,
      @topic,
      {:room_request, room, me |> Identity.pub_key()}
    )

    socket
    |> assign_room_list()
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

        PubSub.broadcast!(
          Chat.PubSub,
          @topic,
          {:room_request_approved, ciphered, user_key, room.pub_key}
        )

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
        encrypted_room_identity,
        user_key,
        room_key
      )
      when my_id == user_key do
    if Map.has_key?(room_map, room_key) do
      socket
    else
      new_room_identity = Rooms.decrypt_identity(encrypted_room_identity, me, room_key)

      time = Chat.Time.monotonic_to_unix(time_offset)
      Rooms.clear_approved_request(new_room_identity, me)
      Log.got_room_key(me, time, new_room_identity |> Identity.pub_key())

      socket
      |> Page.Dialog.store_room_key_copy(new_room_identity)
      |> Page.Login.store_new_room(new_room_identity)
      |> assign_room_list()
    end
  end

  def join_approved_room(socket, _, _, _), do: socket

  def set_db_status(socket, status) do
    socket
    |> assign(:db_status, status)
  end

  def refresh_room_list(socket),
    do:
      socket
      |> assign_room_list()
      |> assign_admin()

  def close(socket) do
    PubSub.unsubscribe(Chat.PubSub, @topic)
    PubSub.unsubscribe(Chat.PubSub, StatusPoller.channel())

    socket
  end

  def process(socket, task) do
    Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
      try do
        socket |> task.()

        :ok
      rescue
        reason ->
          Logger.error([inspect(reason)])
          {:error, task, reason}
      end
    end)

    socket
  end

  defp assign_user_list(socket) do
    socket
    |> assign(:user_id, User.list() |> List.last())
    |> assign(:users, User.list())
  end

  defp assign_room_list(%{assigns: %{room_map: rooms, my_id: my_id}} = socket) do
    {joined, new} = Rooms.list(rooms)

    new =
      Enum.map(new, fn room ->
        Map.put(room, :is_requested?, Rooms.is_requested_by?(room.hash, my_id))
      end)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  defp assign_admin(%{assigns: %{room_map: rooms}} = socket) do
    has_admin_key =
      with admin_pub_key <- AdminRoom.pub_key(),
           false <- is_nil(admin_pub_key),
           some_data <- admin_pub_key |> Enigma.hash(),
           identitiy <- rooms[admin_pub_key],
           false <- is_nil(identitiy),
           sign <- Enigma.sign(some_data, identitiy.private_key),
           true <- Enigma.is_valid_sign?(sign, some_data, admin_pub_key) do
        true
      else
        _ -> false
      end

    socket |> assign(:is_admin, has_admin_key)
  end

  defp close_current_mode(%{assigns: %{lobby_mode: :chats}} = socket),
    do: socket |> Page.Dialog.close()

  defp close_current_mode(%{assigns: %{lobby_mode: :rooms}} = socket),
    do: socket |> Page.Room.close()

  defp close_current_mode(%{assigns: %{lobby_mode: :feeds}} = socket),
    do: socket |> Page.Feed.close()

  defp close_current_mode(%{assigns: %{lobby_mode: :admin}} = socket),
    do: socket |> Page.AdminPanel.close()

  defp close_current_mode(socket), do: socket

  defp init_new_mode(%{assigns: %{lobby_mode: :chats}} = socket), do: socket |> Page.Dialog.init()
  defp init_new_mode(%{assigns: %{lobby_mode: :rooms}} = socket), do: socket |> Page.Room.init()
  defp init_new_mode(%{assigns: %{lobby_mode: :feeds}} = socket), do: socket |> Page.Feed.init()

  defp init_new_mode(%{assigns: %{lobby_mode: :admin}} = socket),
    do: socket |> Page.AdminPanel.init()

  defp approve_pending_requests(%{
         assigns: %{room_map: room_map, me: me, monotonic_offset: time_offset}
       }) do
    for room_key <- Map.keys(room_map),
        %RoomRequest{requester_key: user_key} <- Rooms.list_pending_requests(room_key),
        room = Rooms.approve_request(room_key, user_key, room_map[room_key], public_only: true) do
      case Rooms.get_request(room, user_key) do
        %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
          time = Chat.Time.monotonic_to_unix(time_offset)
          Log.approve_room_request(me, time, room.pub_key)

          PubSub.broadcast!(
            Chat.PubSub,
            @topic,
            {:room_request_approved, ciphered, user_key, room.pub_key}
          )

        _ ->
          :ok
      end
    end
  end

  defp join_approved_requests(%{assigns: %{new_rooms: rooms, my_id: my_id}, root_pid: root_pid}) do
    for %Rooms.Room{} = room <- rooms,
        request <- Rooms.list_approved_requests_for(room, my_id),
        ciphered = request.ciphered_room_identity,
        true == is_bitstring(ciphered) do
      send(root_pid, {:room_request_approved, ciphered, my_id, room.pub_key})
    end
  end

  defp get_version do
    cond do
      ver = System.get_env("RELEASE_SYS_CONFIG") ->
        ver
        |> String.split("/", trim: true)
        |> Enum.at(3)

      ver = System.get_env("SOURCE_VERSION") ->
        "Gigalixir: #{ver}"

      true ->
        "version should be here"
    end
  end
end

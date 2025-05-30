defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"

  import ChatWeb.LiveHelpers, only: [process: 2]
  import Phoenix.Component, only: [assign: 3]
  require Logger

  alias Chat.Broadcast
  alias Chat.Db.ChangeTracker
  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Db.StatusPoller
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Rooms.RoomRequest
  alias Chat.Rooms.RoomsBroker
  alias Chat.User.UsersBroker
  alias ChatWeb.MainLive.Page

  @topic "chat::lobby"

  def init(socket) do
    user_room_approval_topic = Broadcast.Topic.user_room_approval(socket.assigns.my_id)
    PubSub.subscribe(Chat.PubSub, @topic)
    PubSub.subscribe(Chat.PubSub, StatusPoller.channel())
    PubSub.subscribe(Chat.PubSub, user_room_approval_topic)

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign(:image_gallery, nil)
    |> assign(:version, get_version())
    |> assign(:db_status, StatusPoller.info())
    |> assign(:search_filter, :off)
    |> assign_user_list()
    |> assign_room_list()
    |> assign_admin()
    |> process(&approve_pending_requests/1)
    |> process(&join_approved_requests/1)
  end

  def refresh_rooms_and_users(%{assigns: %{search_filter: :on}} = socket), do: socket

  def refresh_rooms_and_users(socket) do
    socket
    |> assign_room_list()
    |> assign_user_list()
  end

  def new_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, name, type)
      when type in [:public, :request, :private, :cargo] do
    {cargo?, type} =
      case type do
        :cargo ->
          {true, :request}

        type ->
          {false, type}
      end

    {new_room_identity, new_room} =
      Rooms.add(me, name, type) |> tap(fn {_, room} -> RoomsBroker.put(room) end)

    new_room_card = Chat.Card.from_identity(new_room_identity)
    send(self(), {:maybe_activate_cargo_room, cargo?, new_room, new_room_identity})

    me |> Log.create_room(Chat.Time.monotonic_to_unix(time_offset), new_room_identity, type)

    ChangeTracker.on_saved(fn ->
      PubSub.broadcast!(Chat.PubSub, @topic, {:new_room, new_room_card})
    end)

    socket
    |> Page.Room.close()
    |> Page.Room.store_new(new_room_identity)
    |> Page.Shared.update_onliners_presence()
    |> Page.Room.init({new_room_identity, new_room})
  end

  @deprecated "Use Chat.Sync.DbBrokers/0 instead"
  def notify_new_user(socket, user_card) do
    ChangeTracker.on_saved(fn ->
      Broadcast.new_user(user_card)
    end)

    socket
  end

  def show_new_user(%{assigns: %{search_filter: :on}} = socket, _), do: socket

  def show_new_user(socket, _user_card) do
    socket
    |> assign_user_list()
  end

  def show_new_room(%{assigns: %{search_filter: :on}} = socket, _), do: socket

  def show_new_room(socket, _room_card) do
    socket
    |> assign_room_list()
  end

  def switch_lobby_mode(socket, mode) do
    socket
    |> close_current_mode()
    |> assign(:search_filter, :off)
    |> assign(:lobby_mode, String.to_existing_atom(mode))
    |> init_new_mode()
  end

  def filter_search_results(socket, %{"_target" => ["reset"], "dialog" => _}) do
    socket
    |> assign(:search_filter, :off)
    |> assign_user_list()
  end

  def filter_search_results(socket, %{"_target" => ["reset"], "room" => _}) do
    socket
    |> assign(:search_filter, :off)
    |> assign_room_list()
  end

  def filter_search_results(socket, %{"dialog" => %{"name" => name}}) do
    socket
    |> assign(:search_filter, :on)
    |> assign_user_list(String.trim(name))
  end

  def filter_search_results(socket, %{"room" => %{"name" => name}}) do
    socket
    |> assign(:search_filter, :on)
    |> assign_room_list(String.trim(name))
  end

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
    user_room_approval_topic = Broadcast.Topic.user_room_approval(socket.assigns.my_id)
    PubSub.unsubscribe(Chat.PubSub, @topic)
    PubSub.unsubscribe(Chat.PubSub, StatusPoller.channel())
    PubSub.unsubscribe(Chat.PubSub, user_room_approval_topic)

    socket
  end

  defp assign_user_list(socket, search_term \\ "")

  defp assign_user_list(%{assigns: %{my_id: id}} = socket, search_term) when search_term == "" do
    socket
    |> assign(
      :users,
      UsersBroker.list()
      |> Enum.split_with(fn card -> card.pub_key == id end)
      |> then(fn {[mine], others} -> [mine | others] end)
    )
  end

  defp assign_user_list(%{assigns: %{my_id: id}} = socket, search_term) do
    socket
    |> assign(
      :users,
      UsersBroker.list(search_term) |> Enum.reject(fn user -> user.pub_key == id end)
    )
  end

  defp assign_room_list(%{assigns: %{room_map: rooms, my_id: my_id}} = socket, search_term \\ "") do
    {joined, new} =
      if search_term == "",
        do: RoomsBroker.list(rooms),
        else: RoomsBroker.list(rooms, search_term)

    new =
      Enum.map(new, fn room ->
        Map.put(room, :is_requested?, Rooms.requested_by?(room.pub_key, my_id))
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
           identity <- rooms[admin_pub_key],
           false <- is_nil(identity),
           sign <- Enigma.sign(some_data, identity.private_key),
           true <- Enigma.valid_sign?(sign, some_data, admin_pub_key) do
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

  defp init_new_mode(%{assigns: %{lobby_mode: :chats}} = socket),
    do: socket |> Page.Dialog.init() |> assign_user_list()

  defp init_new_mode(%{assigns: %{lobby_mode: :rooms}} = socket),
    do: socket |> Page.Room.init() |> assign_room_list()

  defp init_new_mode(%{assigns: %{lobby_mode: :feeds}} = socket),
    do: socket |> Page.Feed.init()

  defp init_new_mode(%{assigns: %{lobby_mode: :admin}} = socket),
    do: socket |> Page.AdminPanel.init()

  defp approve_pending_requests(socket) do
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

  defp join_approved_requests(socket) do
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

defmodule ChatWeb.ProxyLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"

  require Logger

  alias Chat.Broadcast
  alias Chat.Proto
  alias Chat.Rooms

  # import ChatWeb.LiveHelpers, only: [process: 2]
  import Phoenix.Component, only: [assign: 3]
  import Tools.SocketPrivate

  alias ChatWeb.MainLive.Page.Login, as: MainLoginPage
  alias ChatWeb.ProxyLive.Page
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState
  alias ChatWeb.State.ServerRoomsState

  alias Proxy.SocketClient

  def init(socket) do
    # PubSub.subscribe(Chat.PubSub, StatusPoller.channel())

    user_room_approval_topic =
      socket
      |> ActorState.my_pub_key()
      |> Broadcast.Topic.user_room_approval()

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign(:image_gallery, nil)
    |> assign(:version, get_version())
    # |> assign(:db_status, StatusPoller.info())
    |> assign(:search_filter, :off)
    |> set_private(:users_cache, [])
    |> assign_user_list()
    |> assign_room_list()
    # |> assign_admin()
    # |> process(&approve_pending_requests/1)
    # |> process(&join_approved_requests/1)
    |> tap(&make_user_list_request/1)
    |> tap(&make_room_list_request/1)
    |> start_socket_client()
    |> SocketClient.join(user_room_approval_topic)
  end

  def handle_event(msg, params, socket) do
    case msg do
      "lobby/search" -> socket |> filter_search_results(params)
      "room/send-request" -> socket |> send_room_request(params)
      "room/sync-stored" -> socket |> MainLoginPage.sync_stored_room(params)
      _ -> socket |> tap(fn _ -> dbg(msg, params) end)
    end
  end

  def handle_info(msg, socket) do
    case msg do
      {:new_user, user} ->
        socket |> append_user(user)

      {:user_list, list} ->
        socket |> populate_user_list(list)

      {:room_list, list} ->
        socket |> populate_room_list(list)

      {:room_requested, room, requester_pub_key} ->
        socket |> maybe_approve_room_requested(room, requester_pub_key)

      {:room_approved, ciphered, room_key, requester_key} ->
        socket |> join_approved_room(ciphered, room_key, requester_key)
    end
  end

  defp start_socket_client(socket) do
    pid = self()

    SocketClient.connect(socket,
      on_new_user: fn card ->
        send(pid, {:lobby, {:new_user, card}})
      end,
      on_new_dialog_message: fn {dialog_key, indexed_message} ->
        send(pid, {:dialog, {:new_dialog_message, {dialog_key, indexed_message}}})
      end,
      on_room_requested: fn {room, requester_pub_key} ->
        send(pid, {:lobby, {:room_requested, room, requester_pub_key}})
      end,
      on_room_approved: fn {requester_pub_key, {room_key, ciphered}} ->
        send(pid, {:lobby, {:room_approved, ciphered, room_key, requester_pub_key}})
      end
    )
  end

  # def refresh_rooms_and_users(%{assigns: %{search_filter: :on}} = socket), do: socket
  #
  # def refresh_rooms_and_users(socket) do
  #   socket
  #   |> assign_room_list()
  #   |> assign_user_list()
  # end

  # def new_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, name, type)
  #     when type in [:public, :request, :private, :cargo] do
  #   {cargo?, type} =
  #     case type do
  #       :cargo ->
  #         {true, :request}
  #
  #       type ->
  #         {false, type}
  #     end
  #
  #   {new_room_identity, new_room} =
  #     Rooms.add(me, name, type) |> tap(fn {_, room} -> RoomsBroker.put(room) end)
  #
  #   new_room_card = Chat.Card.from_identity(new_room_identity)
  #   send(self(), {:maybe_activate_cargo_room, cargo?, new_room, new_room_identity})
  #
  #   me |> Log.create_room(Chat.Time.monotonic_to_unix(time_offset), new_room_identity, type)
  #
  #   ChangeTracker.on_saved(fn ->
  #     PubSub.broadcast!(Chat.PubSub, @topic, {:new_room, new_room_card})
  #   end)
  #
  #   socket
  #   |> Page.Room.close()
  #   |> Page.Room.store_new(new_room_identity)
  #   |> Page.Shared.update_onliners_presence()
  #   |> Page.Room.init({new_room_identity, new_room})
  # end

  # @deprecated "Use Chat.Sync.DbBrokers/0 instead"
  # def notify_new_user(socket, user_card) do
  #   ChangeTracker.on_saved(fn ->
  #     Chat.Broadcast.new_user(user_card)
  #   end)
  #
  #   socket
  # end
  #
  # def show_new_user(%{assigns: %{search_filter: :on}} = socket, _), do: socket
  #
  # def show_new_user(socket, _user_card) do
  #   socket
  #   |> assign_user_list()
  # end
  #
  def show_new_room(%{assigns: %{search_filter: :on}} = socket, _), do: socket

  def show_new_room(socket, _room_card) do
    socket
    |> assign_room_list()
  end

  def switch_lobby_mode(socket, %{"lobby-mode" => mode}), do: socket |> switch_lobby_mode(mode)

  def switch_lobby_mode(socket, mode) do
    socket
    |> close_current_mode()
    |> assign(:search_filter, :off)
    |> assign(:lobby_mode, String.to_existing_atom(mode))
    |> init_new_mode()
  end

  def filter_search_results(socket, params) do
    case params do
      %{"_target" => ["reset"], "dialog" => _} ->
        socket
        |> assign(:search_filter, :off)
        |> assign_user_list()

      %{"_target" => ["reset"], "room" => _} ->
        socket
        |> assign(:search_filter, :off)
        |> assign_room_list()

      %{"dialog" => %{"name" => name}} ->
        socket
        |> assign(:search_filter, :on)
        |> assign_user_list(String.trim(name))

      %{"room" => %{"name" => name}} ->
        socket
        |> assign(:search_filter, :on)
        |> assign_room_list(String.trim(name))
    end
  end

  defp send_room_request(socket, %{"room" => room_key_raw}) do
    room_key = room_key_raw |> Base.decode16!(case: :lower)

    if not RoomMapState.has_room?(socket, room_key) and
         ServerRoomsState.has_room?(socket, room_key) do
      server = socket |> get_private(:server)
      my_identity = ActorState.my_identity(socket)

      Task.start(fn -> Proxy.request_room(server, my_identity, room_key) end)
    end

    socket
    |> ServerRoomsState.mark_as_requested(room_key)
    |> assign_room_list()
  end

  # should send updated room as from room update broadcast

  # def request_room(
  #       %{assigns: %{me: me, monotonic_offset: time_offset, new_rooms: rooms}} = socket,
  #       room_key
  #     ) do
  #   time = Chat.Time.monotonic_to_unix(time_offset)
  #
  #   room =
  #     Rooms.add_request(room_key, me, time, fn req_message ->
  #       Page.Room.broadcast_new_message(req_message, room_key, me, time)
  #     end)
  #
  #   Rooms.RoomsBroker.put(room)
  #
  #   Log.request_room_key(me, time, room.pub_key)
  #
  #   PubSub.broadcast!(
  #     Chat.PubSub,
  #     @topic,
  #     {:room_request, room, me |> Identity.pub_key()}
  #   )
  #
  #   socket
  #   |> assign(
  #     :new_rooms,
  #     Enum.map(rooms, fn
  #       %{pub_key: pub_key} when pub_key == room.pub_key -> Map.put(room, :is_requested?, true)
  #       other_room -> other_room
  #     end)
  #   )
  # end
  #

  def maybe_approve_room_requested(socket, room, user_key) do
    room_key = room |> Proto.Identify.pub_key()
    room_identity = socket.assigns.room_map[room_key]

    room_is_valid_for_approval? =
      room_identity and
        room.type == :public and
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

  # def approve_room_request(
  #       %{assigns: %{room_map: room_map, me: me, monotonic_offset: time_offset}} = socket,
  #       room_or_hash,
  #       user_key
  #     ) do
  #   room =
  #     case room_or_hash do
  #       %Rooms.Room{} = room ->
  #         Rooms.approve_request(room, user_key, room_map[room.pub_key], public_only: true)
  #
  #       room_hash ->
  #         room_key = room_hash |> Base.decode16!(case: :lower)
  #         Rooms.approve_request(room_key, user_key, room_map[room_key], public_only: true)
  #     end
  #
  #   case Rooms.get_request(room, user_key) do
  #     %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
  #       time = Chat.Time.monotonic_to_unix(time_offset)
  #       Log.approve_room_request(me, time, room.pub_key)
  #
  #       PubSub.broadcast!(
  #         Chat.PubSub,
  #         @topic,
  #         {:room_request_approved, ciphered, user_key, room.pub_key}
  #       )
  #
  #     _ ->
  #       :ok
  #   end
  #
  #   socket
  # rescue
  #   _ -> socket
  # end
  #
  #

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

  # def join_approved_room(
  #       %{assigns: %{me: me, my_id: my_id, monotonic_offset: time_offset, room_map: room_map}} =
  #         socket,
  #       ciphered_room_identity,
  #       user_key,
  #       room_key
  #     )
  #     when my_id == user_key do
  #   if Map.has_key?(room_map, room_key) do
  #     socket
  #   else
  #     new_room_identity = Rooms.decipher_identity_with_key(ciphered_room_identity, me, room_key)
  #
  #     time = Chat.Time.monotonic_to_unix(time_offset)
  #     Rooms.clear_approved_request(new_room_identity, me)
  #     Log.got_room_key(me, time, new_room_identity |> Identity.pub_key())
  #
  #     socket
  #     |> Page.Room.store_new(new_room_identity)
  #   end
  # end
  #
  # def join_approved_room(socket, _, _, _), do: socket
  #
  # def set_db_status(socket, status) do
  #   socket
  #   |> assign(:db_status, status)
  # end
  #
  # def refresh_room_list(socket),
  #   do:
  #     socket
  #     |> assign_room_list()
  #     |> assign_admin()

  def close(socket) do
    # PubSub.unsubscribe(Chat.PubSub, @topic)
    # PubSub.unsubscribe(Chat.PubSub, StatusPoller.channel())

    topic =
      socket
      |> ActorState.my_pub_key()
      |> Chat.Broadcast.Topic.user_room_approval()

    socket
    |> SocketClient.leave(topic)
  end

  defp assign_user_list(socket, search_term \\ "") do
    cache = socket |> get_private(:users_cache, [])

    user_list =
      case search_term do
        "" -> me_first_and_user_list(cache, ActorState.my_pub_key(socket))
        search_term -> matching_user_list(cache, search_term)
      end

    socket
    |> assign(:users, user_list)
  end

  defp me_first_and_user_list(cache, my_pubkey) do
    cache
    |> Enum.split_with(fn card -> card.pub_key == my_pubkey end)
    |> then(fn
      {[mine], others} -> [mine | others]
      {[], others} -> others
    end)
  end

  defp matching_user_list(cache, search_term) do
    cache
    |> Enum.filter(fn card -> String.contains?(card.name, search_term) end)
  end

  defp assign_room_list(socket, search_term \\ "") do
    {joined, new} = ServerRoomsState.get_room_lists(socket, search_term)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  # defp assign_admin(%{assigns: %{room_map: rooms}} = socket) do
  #   has_admin_key =
  #     with admin_pub_key <- AdminRoom.pub_key(),
  #          false <- is_nil(admin_pub_key),
  #          some_data <- admin_pub_key |> Enigma.hash(),
  #          identity <- rooms[admin_pub_key],
  #          false <- is_nil(identity),
  #          sign <- Enigma.sign(some_data, identity.private_key),
  #          true <- Enigma.valid_sign?(sign, some_data, admin_pub_key) do
  #       true
  #     else
  #       _ -> false
  #     end
  #
  #   socket |> assign(:is_admin, has_admin_key)
  # end

  defp close_current_mode(%{assigns: %{lobby_mode: mode}} = socket) do
    case mode do
      :chats -> socket |> Page.Dialog.close()
      :rooms -> socket |> Page.Room.close()
      _ -> socket
    end

    # :feed -> socket |> Page.Feed.close()
    # :admin -> socket |> Page.AdminPanel.close()
  end

  defp init_new_mode(%{assigns: %{lobby_mode: new_mode}} = socket) do
    case new_mode do
      :chats -> socket |> Page.Dialog.init() |> assign_user_list()
      :rooms -> socket |> Page.Room.init() |> assign_room_list()
    end

    # :feed -> socket |> Page.Feed.init()
    # :admin -> socket |> Page.AdminPanel.init()
  end

  # defp approve_pending_requests(socket) do
  #   %{room_map: room_map, me: me, monotonic_offset: time_offset} = socket.assigns
  #
  #   for room_key <- Map.keys(room_map),
  #       %RoomRequest{requester_key: user_key} <- Rooms.list_pending_requests(room_key),
  #       room = Rooms.approve_request(room_key, user_key, room_map[room_key], public_only: true) do
  #     Rooms.RoomsBroker.put(room)
  #
  #     case Rooms.get_request(room, user_key) do
  #       %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
  #         time = Chat.Time.monotonic_to_unix(time_offset)
  #         Log.approve_room_request(me, time, room.pub_key)
  #
  #         PubSub.broadcast!(
  #           Chat.PubSub,
  #           @topic,
  #           {:room_request_approved, ciphered, user_key, room.pub_key}
  #         )
  #
  #       _ ->
  #         :ok
  #     end
  #   end
  # rescue
  #   _ -> :skip
  # end
  #
  # defp join_approved_requests(socket) do
  #   %{new_rooms: rooms, my_id: my_id} = socket.assigns
  #   root_pid = socket.root_pid
  #
  #   for %Rooms.Room{} = room <- rooms,
  #       request <- Rooms.list_approved_requests_for(room, my_id),
  #       ciphered = request.ciphered_room_identity,
  #       true == is_bitstring(ciphered) do
  #     send(root_pid, {:room_request_approved, ciphered, my_id, room.pub_key})
  #   end
  # rescue
  #   _ -> :skip
  # end

  defp join_approved_requests(socket) do
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

  defp make_user_list_request(socket) do
    server = socket |> get_private(:server)

    request_user_list(server, ActorState.my_identity(socket))
  end

  defp request_user_list(server, me) do
    pid = self()

    Task.start(fn ->
      Proxy.register_me(server, me)
      users = Proxy.get_users(server)

      if is_list(users) do
        send(pid, {:lobby, {:user_list, users}})
      end
    end)
  end

  defp populate_user_list(socket, user_list) do
    socket
    |> set_private(:users_cache, user_list)
    |> assign_user_list()
  end

  defp append_user(socket, user) do
    users_cache = socket |> get_private(:users_cache)

    socket
    |> set_private(:users_cache, [user | users_cache] |> Enum.uniq())
    |> assign_user_list()
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

  defp make_room_list_request(socket) do
    server = socket |> get_private(:server)
    pid = self()

    Task.start(fn ->
      rooms = Proxy.get_rooms(server)

      if is_list(rooms) do
        send(pid, {:lobby, {:room_list, rooms}})
      end
    end)
  end

  defp populate_room_list(socket, room_list) do
    socket
    |> ServerRoomsState.set(room_list)
    |> assign_room_list()
    |> join_approved_requests()
    |> assign_room_list()
  end

  #
  # defp append_room_list(socket, room) do
  #   socket
  #   |> ServerRoomsState.insert_room(room)
  #   |> assign_room_list()
  # end
end

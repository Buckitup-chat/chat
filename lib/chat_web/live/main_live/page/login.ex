defmodule ChatWeb.MainLive.Page.Login do
  @moduledoc "Login part of chat"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  require Logger

  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Sync.DbBrokers
  alias Chat.User
  alias Chat.User.UsersBroker

  alias ChatWeb.MainLive.Index

  @local_store_auth_key "buckitUp-chat-auth-v2"
  @local_store_room_count_key "buckitUp-room-count-v2"

  def handshaked(socket), do: socket |> assign(:handshaked, true)

  def create_user(socket, name) do
    me =
      name
      |> String.trim()
      |> User.login()
      |> tap(&User.register/1)
      |> tap(fn identity ->
        identity
        |> Chat.Card.from_identity()
        |> Chat.Broadcast.new_user()
      end)
      |> tap(fn _ -> DbBrokers.broadcast_refresh() end)

    # todo: check setting time before creating
    Log.sign_in(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me)
    |> store()
    |> close()
  end

  def load_user(socket, %{"auth" => data} = params) do
    {me, rooms} = User.device_decode(data)

    socket
    |> load_user(me, rooms)
    |> assign(:room_count_to_backup, Map.get(params, "room_count", 0))
    |> assign(:legal_notice_accepted, Map.get(params, "legal_notice_accepted", "") == "true")
  end

  def load_user(socket, x) do
    x |> inspect() |> Logger.warning()

    socket
  end

  def load_user(socket, %Identity{} = me, rooms) do
    me
    |> User.login()
    |> tap(&User.register/1)
    |> tap(&UsersBroker.put/1)
    |> tap(fn identity ->
      identity
      |> Chat.Card.from_identity()
      |> Chat.Broadcast.new_user()
    end)
    |> tap(fn _ -> DbBrokers.broadcast_refresh() end)

    PubSub.subscribe(Chat.PubSub, login_topic(me))
    Log.visit(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me, rooms)
    |> close()
  end

  def load_user(socket, x, y) do
    {x, y} |> inspect() |> Logger.warning()

    socket
  end

  def sync_stored_room(%{assigns: %{me: me}} = socket, %{"room_count" => count, "key" => key}) do
    PubSub.broadcast_from(Chat.PubSub, self(), login_topic(me), {:sync_stored_room, key, count})

    # me
    #   |> Broadcast.Topic.login()
    #   |> Broadcast.sync_stored_room(key, count)
    socket
    |> assign(:room_count_to_backup, count)
  end

  def store_new_room(%{assigns: %{rooms: rooms, room_map: room_map}} = socket, new_room_identity) do
    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> assign(
      :room_map,
      Map.put(room_map, new_room_identity |> Identity.pub_key(), new_room_identity)
    )
    |> push_event("store-room", %{
      auth_key: @local_store_auth_key,
      room_count_key: @local_store_room_count_key,
      room_key: Identity.priv_key_to_string(new_room_identity),
      reply: "room/sync-stored"
    })
  end

  def store_new_room_on_client(socket, new_room_identity) do
    socket
    |> push_event("store-room", %{
      auth_key: @local_store_auth_key,
      room_count_key: @local_store_room_count_key,
      room_key: Identity.priv_key_to_string(new_room_identity),
      reply: "room/sync-stored"
    })
  end

  def store(%{assigns: %{rooms: rooms, me: me}} = socket) do
    socket
    |> push_event("store", %{
      auth_key: @local_store_auth_key,
      auth_data:
        User.device_encode(
          me,
          rooms,
          Map.get(socket.assigns, :contacts, %{}),
          Map.get(socket.assigns, :payload, %{})
        ),
      room_count_key: @local_store_room_count_key,
      room_count: 0
    })
    |> assign(:room_count_to_backup, 0)
  end

  def clear(%{assigns: %{rooms: _rooms, me: me}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, login_topic(me))

    socket
    |> push_event("clear", %{
      auth_key: @local_store_auth_key,
      room_count_key: @local_store_room_count_key
    })
  end

  def check_stored(socket) do
    cond do
      already_loaded_client_storage?(socket) -> socket
      params = client_storage_in_params(socket) -> emulate_restore_auth(socket, params)
      true -> request_restore(socket)
    end
  end

  defp already_loaded_client_storage?(socket) do
    match?(%{assigns: %{me: _}}, socket)
  end

  defp client_storage_in_params(socket) do
    %{"storage" => storage} = Phoenix.LiveView.get_connect_params(socket)
    storage
  rescue
    _ -> nil
  end

  defp emulate_restore_auth(socket, params) do
    {:noreply, socket} = Index.handle_event("restoreAuth", params, socket)
    socket |> request_restore()
  end

  defp request_restore(socket) do
    socket
  end

  def sync_stored_room(
        %{assigns: %{rooms: rooms, room_map: room_map}} = socket,
        key_string,
        room_count
      ) do
    new_room_identity = Identity.from_strings(["", key_string])

    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> assign(
      :room_map,
      Map.put(room_map, new_room_identity |> Identity.pub_key(), new_room_identity)
    )
    |> assign(:room_count_to_backup, room_count)
  end

  def reset_rooms_to_backup(%{assigns: %{me: me}} = socket, opts \\ []) do
    if Keyword.get(opts, :sync, false) do
      PubSub.broadcast_from(Chat.PubSub, self(), login_topic(me), :reset_rooms_to_backup)

      socket
      |> push_event("reset-rooms-to-backup", %{key: @local_store_room_count_key})
    else
      socket
    end
    |> assign(:room_count_to_backup, 0)
  end

  defp login_topic(person),
    do: "login:" <> (person |> Enigma.hash() |> Base.encode16(case: :lower))

  defp assign_logged_user(socket, me, rooms \\ []) do
    socket
    |> assign(:me, me)
    |> assign(:my_id, Identity.pub_key(me))
    |> assign_rooms(rooms)
    |> maybe_create_admin_room()
  end

  def close(socket) do
    socket
    |> assign(:need_login, false)
  end

  defp assign_rooms(socket, rooms) do
    socket
    |> assign(:rooms, rooms)
    |> assign(
      :room_map,
      rooms |> Enum.map(fn room -> {room.public_key, room} end) |> Map.new()
    )
  end

  defp maybe_create_admin_room(socket) do
    if AdminRoom.created?() do
      socket
    else
      socket
      |> store_new_room(AdminRoom.create())
    end
  end
end

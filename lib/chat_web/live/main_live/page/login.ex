defmodule ChatWeb.MainLive.Page.Login do
  @moduledoc "Login part of chat"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Identity
  alias Chat.Log
  alias Chat.User
  alias Chat.Utils
  alias ChatWeb.MainLive.Page

  @local_store_auth_key "buckitUp-chat-auth"
  @local_store_room_count_key "buckitUp-room-count"

  def handshaked(socket), do: socket |> assign(:handshaked, true)

  def create_user(socket, name) do
    me = User.login(name |> String.trim())
    id = User.register(me)
    # todo: check setting time before creating
    Log.sign_in(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me, id)
    |> store()
    |> close()
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def load_user(socket, %{"auth" => data, "room_count" => room_count}) do
    {me, rooms} = User.device_decode(data)

    socket
    |> load_user(me, rooms)
    |> assign(:room_count_to_backup, room_count)
  end

  def load_user(socket, %Identity{} = me, rooms) do
    id =
      me
      |> User.login()
      |> User.register()

    PubSub.subscribe(Chat.PubSub, login_topic(me))
    Log.visit(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me, id, rooms)
    |> close()
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def sync_stored_room(%{assigns: %{me: me}} = socket, %{"room_count" => count, "key" => key}) do
    PubSub.broadcast_from(Chat.PubSub, self(), login_topic(me), {:sync_stored_room, key, count})

    socket
    |> assign(:room_count_to_backup, count)
  end

  def store_new_room(%{assigns: %{rooms: rooms, room_map: room_map}} = socket, new_room_identity) do
    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> assign(:room_map, Map.put(room_map, Utils.hash(new_room_identity), new_room_identity))
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
      auth_data: User.device_encode(me, rooms),
      room_count_key: @local_store_room_count_key,
      room_count: 0
    })
    |> assign(:room_count_to_backup, 0)
  end

  def clear(%{assigns: %{rooms: _rooms, me: me}} = socket, opts \\ []) do
    topic = login_topic(me)
    sync = Keyword.get(opts, :sync, false)

    if sync, do: PubSub.broadcast_from(Chat.PubSub, self(), topic, :refresh)
    PubSub.unsubscribe(Chat.PubSub, topic)

    socket
    |> push_event("clear", %{
      auth_key: @local_store_auth_key,
      room_count_key: @local_store_room_count_key
    })
  end

  def check_stored(socket) do
    socket
    |> push_event("restore", %{
      auth_key: @local_store_auth_key,
      room_count_key: @local_store_room_count_key,
      event: "restoreAuth"
    })
  end

  def sync_stored_room(
        %{assigns: %{rooms: rooms, room_map: room_map}} = socket,
        key_string,
        room_count
      ) do
    new_room_identity = Identity.from_strings(["", key_string])

    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> assign(:room_map, Map.put(room_map, Utils.hash(new_room_identity), new_room_identity))
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

  defp login_topic(person), do: "login:" <> Utils.hash(person)

  defp assign_logged_user(socket, me, id, rooms \\ []) do
    socket
    |> assign(:me, me)
    |> assign(:my_id, id)
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
      rooms |> Enum.map(fn room -> {room |> Utils.hash(), room} end) |> Map.new()
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

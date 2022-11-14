defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.LiveView, only: [assign: 3]

  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils
  alias ChatWeb.MainLive.Page

  @topic "chat::lobby"

  def init(socket) do
    PubSub.subscribe(Chat.PubSub, @topic)
    PubSub.subscribe(Chat.PubSub, Chat.Db.StatusPoller.channel())

    Process.send_after(self(), :room_request, 500)
    Process.send_after(self(), :room_request_approved, 1500)

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign(:image_gallery, nil)
    |> assign(:version, get_version())
    |> assign(:db_status, Chat.Db.StatusPoller.info())
    |> assign_user_list()
    |> assign_room_list()
    |> assign_admin()
  end

  def new_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, name, type)
      when type in [:public, :request, :private] do
    new_room_identity = Rooms.add(me, name, type)
    new_room_card = Chat.Card.from_identity(new_room_identity)

    me |> Log.create_room(Chat.Time.monotonic_to_unix(time_offset), new_room_identity, type)
    PubSub.broadcast!(Chat.PubSub, @topic, {:new_room, new_room_card})

    socket
    |> Page.Login.store_new_room(new_room_identity)
    |> assign_room_list()
    |> Page.Room.init(new_room_card.hash)
  end

  def notify_new_user(socket, user_card) do
    PubSub.broadcast!(
      Chat.PubSub,
      @topic,
      {:new_user, user_card}
    )

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

  def request_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, room_hash) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    room = Rooms.add_request(room_hash, me, time)
    Log.request_room_key(me, time, room.pub_key)

    PubSub.broadcast!(
      Chat.PubSub,
      @topic,
      :room_request
    )

    socket
    |> assign_room_list()
  end

  def approve_requests(socket) do
    socket
    |> approve_joined_room_requests()
  end

  def join_rooms(socket) do
    socket
    |> join_approved_rooms()
  end

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
    PubSub.unsubscribe(Chat.PubSub, Chat.Db.StatusPoller.channel())

    socket
  end

  defp assign_user_list(socket) do
    socket
    |> assign(:user_id, User.list() |> List.last())
    |> assign(:users, User.list())
  end

  defp assign_room_list(%{assigns: %{rooms: rooms}} = socket) do
    {joined, new} = Rooms.list(rooms)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  defp assign_admin(%{assigns: %{room_map: rooms}} = socket) do
    has_admin_key =
      with admin_pub_key <- AdminRoom.pub_key(),
           false <- is_nil(admin_pub_key),
           admin_hash <- admin_pub_key |> Utils.hash(),
           identitiy <- rooms[admin_hash],
           false <- is_nil(identitiy),
           sign <- Utils.sign(admin_hash, identitiy),
           true <- Utils.is_signed_by?(sign, admin_hash, admin_pub_key) do
        true
      else
        _ -> false
      end

    socket |> assign(:is_admin, has_admin_key)
  end

  defp approve_joined_room_requests(%{assigns: %{rooms: rooms}} = socket) do
    rooms
    |> Enum.each(fn room_identity ->
      room_identity
      |> Identity.pub_key()
      |> Utils.hash()
      |> Rooms.approve_requests(room_identity)
    end)

    PubSub.broadcast!(
      Chat.PubSub,
      @topic,
      :room_request_approved
    )

    socket
  end

  defp join_approved_rooms(
         %{assigns: %{new_rooms: new_rooms, rooms: rooms, me: me, monotonic_offset: time_offset}} =
           socket
       ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    joined_rooms =
      new_rooms
      |> Enum.flat_map(fn %{hash: hash} -> hash |> Rooms.join_approved_requests(me, time) end)

    socket
    |> assign(:rooms, joined_rooms ++ rooms)
    |> Page.Login.store()
    |> assign_room_list()
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

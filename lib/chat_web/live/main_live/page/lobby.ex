defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.LiveView, only: [assign: 3]

  alias Phoenix.PubSub

  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils
  alias ChatWeb.MainLive.Page

  @topic "chat::lobby"

  def init(socket) do
    PubSub.subscribe(Chat.PubSub, @topic)

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign_user_list()
    |> approve_joined_room_requests()
    |> assign_room_list()
    |> join_approved_rooms()
  end

  def new_room(%{assigns: %{me: me, rooms: rooms}} = socket, name) do
    new_room_identity = Rooms.add(me, name)
    new_room_card = Chat.Card.from_identity(new_room_identity)

    PubSub.broadcast!(Chat.PubSub, @topic, {:new_room, new_room_card})

    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> Page.Login.store()
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
    |> assign(:lobby_mode, String.to_atom(mode))
    |> init_new_mode()
  end

  def request_room(%{assigns: %{me: me}} = socket, room_hash) do
    Rooms.add_request(room_hash, me)

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

  def close(socket) do
    PubSub.unsubscribe(Chat.PubSub, @topic)

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

  defp join_approved_rooms(%{assigns: %{new_rooms: new_rooms, rooms: rooms, me: me}} = socket) do
    joined_rooms =
      new_rooms
      |> Enum.flat_map(fn %{hash: hash} -> hash |> Rooms.join_approved_requests(me) end)

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

  defp init_new_mode(%{assigns: %{lobby_mode: :chats}} = socket), do: socket |> Page.Dialog.init()
  defp init_new_mode(%{assigns: %{lobby_mode: :rooms}} = socket), do: socket |> Page.Room.init()
  defp init_new_mode(%{assigns: %{lobby_mode: :feeds}} = socket), do: socket |> Page.Feed.init()
end

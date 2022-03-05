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
    |> assign(:mode, :user_list)
    |> assign_user_list()
    |> approve_joined_room_requests()
    |> assign_room_list()
    |> join_approved_rooms()
  end

  def new_room(%{assigns: %{me: me, rooms: rooms}} = socket, name) do
    new_room_identity = Rooms.add(me, name)

    PubSub.broadcast!(
      Chat.PubSub,
      @topic,
      {:new_room, new_room_identity |> Chat.Card.from_identity()}
    )

    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> Page.Login.store()
    |> assign_room_list()
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
end

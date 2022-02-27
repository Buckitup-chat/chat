defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.LiveView, only: [assign: 3]

  alias Phoenix.PubSub

  alias Chat.Rooms
  alias Chat.User
  alias ChatWeb.MainLive.Page

  @topic "chat::lobby"

  def init(socket) do
    PubSub.subscribe(Chat.PubSub, @topic)

    socket
    |> assign(:mode, :user_list)
    |> assign_user_list()
    |> assign_room_list()
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
end

defmodule ChatWeb.MainLive.Page.Lobby do
  @moduledoc """
  Lobby part of chat: opening and closing the lobby, switching lobby modes, search,
  and refreshing the lists. Also the stable entry point for the lobby router and the
  other pages, which delegates to:

  - `ChatWeb.MainLive.Page.Lobby.Users` — the user list
  - `ChatWeb.MainLive.Page.Lobby.Rooms` — creating rooms, the room list, admin key check
  - `ChatWeb.MainLive.Page.Lobby.RoomRequests` — requesting, approving and joining rooms
  """

  import ChatWeb.LiveHelpers, only: [process: 2]

  import ChatWeb.MainLive.Page.Lobby.Rooms,
    only: [assign_room_list: 1, assign_room_list: 2, assign_admin: 1]

  import ChatWeb.MainLive.Page.Lobby.Users, only: [assign_user_list: 1, assign_user_list: 2]
  import Phoenix.Component, only: [assign: 3]

  alias Chat.Broadcast
  alias Chat.Db.ChangeTracker
  alias Chat.Db.StatusPoller
  alias ChatWeb.MainLive.Page
  alias ChatWeb.MainLive.Page.Lobby.RoomRequests
  alias ChatWeb.MainLive.Page.Lobby.Rooms
  alias Phoenix.PubSub

  @topic "chat::lobby"

  defdelegate new_room(socket, name, type), to: Rooms

  defdelegate request_room(socket, room_key), to: RoomRequests
  defdelegate approve_room_request(socket, room_or_hash, user_key), to: RoomRequests

  defdelegate join_approved_room(socket, ciphered_room_identity, user_key, room_key),
    to: RoomRequests

  @doc "PubSub topic of lobby-wide events (new rooms)."
  def topic, do: @topic

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
    |> process(&RoomRequests.approve_pending_requests/1)
    |> process(&RoomRequests.join_approved_requests/1)
  end

  def refresh_rooms_and_users(%{assigns: %{search_filter: :on}} = socket), do: socket

  def refresh_rooms_and_users(socket) do
    socket
    |> assign_room_list()
    |> assign_user_list()
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

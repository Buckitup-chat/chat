defmodule ChatWeb.ProxyLive.Page.Lobby do
  @moduledoc """
  Lobby part of the proxy chat: entry point for lobby events and socket client messages,
  lobby mode switching and search.

  User list, room list and room requests live in `ChatWeb.ProxyLive.Page.Lobby.Users`,
  `ChatWeb.ProxyLive.Page.Lobby.Rooms` and `ChatWeb.ProxyLive.Page.Lobby.RoomRequests`.
  """

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Tools.SocketPrivate

  alias Chat.Broadcast
  alias ChatWeb.MainLive.Page.Login, as: MainLoginPage
  alias ChatWeb.ProxyLive.Page
  alias ChatWeb.ProxyLive.Page.Lobby.RoomRequests
  alias ChatWeb.ProxyLive.Page.Lobby.Rooms
  alias ChatWeb.ProxyLive.Page.Lobby.Users
  alias ChatWeb.State.ActorState
  alias Proxy.SocketClient

  defdelegate maybe_approve_room_requested(socket, room, user_key), to: RoomRequests

  defdelegate join_approved_room(socket, ciphered_room_identity, room_key, user_key),
    to: RoomRequests

  def init(socket) do
    user_room_approval_topic =
      socket
      |> ActorState.my_pub_key()
      |> Broadcast.Topic.user_room_approval()

    socket
    |> assign(:mode, :lobby)
    |> assign(:lobby_mode, :chats)
    |> assign(:image_gallery, nil)
    |> assign(:version, get_version())
    |> assign(:search_filter, :off)
    |> set_private(:users_cache, [])
    |> Users.assign_user_list()
    |> Rooms.assign_room_list()
    |> tap(&Users.make_user_list_request/1)
    |> tap(&Rooms.make_room_list_request/1)
    |> start_socket_client()
    |> SocketClient.join(user_room_approval_topic)
  end

  def handle_event(msg, params, socket) do
    case msg do
      "lobby/search" ->
        socket |> filter_search_results(params)

      "room/send-request" ->
        socket |> RoomRequests.send_room_request(params)

      "room/sync-stored" ->
        socket |> MainLoginPage.sync_stored_room(params)

      _ ->
        socket
        |> tap(fn _ -> Logger.warning(["unhandled lobby event ", inspect({msg, params})]) end)
    end
  end

  def handle_info(msg, socket) do
    case msg do
      {:new_user, user} ->
        socket |> Users.append_user(user)

      {:user_list, list} ->
        socket |> Users.populate_user_list(list)

      {:room_list, list} ->
        socket |> Rooms.populate_room_list(list)

      {:room_requested, room, requester_pub_key} ->
        socket |> RoomRequests.maybe_approve_room_requested(room, requester_pub_key)

      {:room_approved, ciphered, room_key, requester_key} ->
        socket |> RoomRequests.join_approved_room(ciphered, room_key, requester_key)
    end
  end

  def show_new_room(%{assigns: %{search_filter: :on}} = socket, _), do: socket

  def show_new_room(socket, _room_card) do
    socket
    |> Rooms.assign_room_list()
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
        |> Users.assign_user_list()

      %{"_target" => ["reset"], "room" => _} ->
        socket
        |> assign(:search_filter, :off)
        |> Rooms.assign_room_list()

      %{"dialog" => %{"name" => name}} ->
        socket
        |> assign(:search_filter, :on)
        |> Users.assign_user_list(String.trim(name))

      %{"room" => %{"name" => name}} ->
        socket
        |> assign(:search_filter, :on)
        |> Rooms.assign_room_list(String.trim(name))
    end
  end

  def close(socket) do
    topic =
      socket
      |> ActorState.my_pub_key()
      |> Chat.Broadcast.Topic.user_room_approval()

    socket
    |> SocketClient.leave(topic)
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

  defp close_current_mode(%{assigns: %{lobby_mode: mode}} = socket) do
    case mode do
      :chats -> socket |> Page.Dialog.close()
      :rooms -> socket |> Page.Room.close()
      _ -> socket
    end
  end

  defp init_new_mode(%{assigns: %{lobby_mode: new_mode}} = socket) do
    case new_mode do
      :chats -> socket |> Page.Dialog.init() |> Users.assign_user_list()
      :rooms -> socket |> Page.Room.init() |> Rooms.assign_room_list()
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

defmodule ChatWeb.MainLive.Page.LobbyRouter do
  @moduledoc """
  Route lobby events and messages of `ChatWeb.MainLive.Index`: lobby mode switching, search,
  history paging, data restore, new users/rooms and room requests.

  Siblings: `LoginRouter`, `LogoutRouter`, `SyncRoomRouter`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"switch-lobby-mode", %{"lobby-mode" => mode}} ->
        socket
        |> Page.Lobby.switch_lobby_mode(mode)
        |> Page.Room.init()

      {"lobby/search", params} ->
        socket |> Page.Lobby.filter_search_results(params)

      {"chat:load-more", _} ->
        socket |> load_more_messages()

      {"feed-more", _} ->
        socket |> Page.Feed.more()

      {"open-data-restore", _} ->
        socket |> assign(:mode, :restore_data)

      {"backup-file-submit", _} ->
        socket

      {"close-data-restore", _} ->
        socket |> assign(:mode, :lobby)
    end
  end

  defp load_more_messages(%{assigns: %{dialog: %{}}} = socket),
    do: socket |> Page.Dialog.load_more_messages()

  defp load_more_messages(%{assigns: %{room: %{}}} = socket),
    do: socket |> Page.Room.load_more_messages()

  #
  # Process messages
  #

  def info(socket, message) do
    case message do
      {:new_user, card} ->
        socket |> Page.Lobby.show_new_user(card)

      {:new_room, card} ->
        socket |> Page.Lobby.show_new_room(card)

      {:room_request, room_key, user_key} ->
        socket |> Page.Lobby.approve_room_request(room_key, user_key)

      {:room_request_approved, encrypted_room_entity, user_key, room_key} ->
        socket |> Page.Lobby.join_approved_room(encrypted_room_entity, user_key, room_key)

      {:create_new_room, %{name: name, type: type}} ->
        socket
        |> Page.Lobby.new_room(name, type)
        |> Page.Room.maybe_enable_cargo()
        |> Page.Room.maybe_enable_usb_drive_dump()

      {:lobby, :refresh_rooms_and_users} ->
        socket |> Page.Lobby.refresh_rooms_and_users()

      {:db_status, msg} ->
        socket |> Page.Lobby.set_db_status(msg)
    end
  end
end

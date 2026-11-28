defmodule ChatWeb.MainLive.Page.LiveRouter do
  @moduledoc "Routes live actions"

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias ChatWeb.MainLive.Page

  @doc "Store link params of the live action and route it once the user is logged in"
  def params(socket, params) do
    case {socket.assigns[:live_action], params} do
      {:room_message_link, %{"hash" => hash}} ->
        socket
        |> assign(:room_message_link_hash, hash)
        |> action_when_logged_in()

      {:chat_link, %{"hash" => hash}} ->
        socket
        |> assign(:chat_link, hash)
        |> action_when_logged_in()

      {:rooms, _} ->
        socket |> action_when_logged_in()

      {:chats, _} ->
        socket |> action_when_logged_in()

      _ ->
        socket
    end
  end

  defp action_when_logged_in(socket) do
    if connected?(socket) and not socket.assigns.need_login,
      do: action(socket),
      else: socket
  end

  def action(%{assigns: assigns} = socket) do
    case assigns do
      %{live_action: :chat_link, chat_link: hash} ->
        socket |> Page.Dialog.init(hash)

      %{live_action: :room_message_link, room_message_link_hash: hash} ->
        socket |> Page.Room.init_with_linked_message(hash)

      %{live_action: :chats} ->
        Process.send_after(self(), {:push_patch, "/trusted"}, 250)

        socket
        |> Page.Lobby.switch_lobby_mode("chats")

      %{live_action: :rooms} ->
        Process.send_after(self(), {:push_patch, "/trusted"}, 250)

        socket
        |> Page.Lobby.switch_lobby_mode("rooms")

      _ ->
        socket
    end
  end
end

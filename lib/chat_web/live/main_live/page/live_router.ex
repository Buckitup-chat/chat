defmodule ChatWeb.MainLive.Page.LiveRouter do
  @moduledoc "Routes live actions"

  alias ChatWeb.MainLive.Page

  def action(%{assigns: assigns} = socket) do
    case assigns do
      %{live_action: :chat_link, chat_link: hash} ->
        socket |> Page.Dialog.init(hash)

      %{live_action: :room_message_link, room_message_link_hash: hash} ->
        socket |> Page.Room.init_with_linked_message(hash)

      %{live_action: :chats} ->
        Process.send_after(self(), {:push_patch, "/"}, 250)

        socket
        |> Page.Lobby.switch_lobby_mode("chats")

      %{live_action: :rooms} ->
        Process.send_after(self(), {:push_patch, "/"}, 250)

        socket
        |> Page.Lobby.switch_lobby_mode("rooms")

      _ ->
        socket
    end
  end
end

defmodule ChatWeb.MainLive.Page.LiveRouter do
  @moduledoc "Routes live actions"

  alias ChatWeb.MainLive.Page

  def action(%{assigns: assigns} = socket) do
    case assigns do
      %{live_action: :chat_link, chat_link: hash} ->
        socket |> Page.Dialog.init(hash)

      %{live_action: :room_message_link, room_message_link_hash: hash} ->
        socket |> Page.Room.init_with_linked_message(hash)

      _ ->
        socket
    end
  end
end

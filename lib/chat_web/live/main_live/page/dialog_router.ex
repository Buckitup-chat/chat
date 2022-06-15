defmodule ChatWeb.MainLive.Page.DialogRouter do
  @moduledoc "Route dialog events"

  import Phoenix.LiveView, only: [push_event: 3]
  alias ChatWeb.MainLive.Index
  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"accept-room-invite", %{"id" => id, "time" => time}} ->
        socket |> Page.Dialog.accept_room_invite({time |> String.to_integer(), id})

      {"accept-room-invite-and-open-room", %{"id" => id, "time" => time}} ->
        socket |> Page.Dialog.accept_room_invite_and_open_room({time |> String.to_integer(), id})

      {"import-images", _} ->
        socket |> push_event("chat:scroll-down", %{})

      {"import-files", _} ->
        socket |> push_event("chat:scroll-down", %{})

      {"cancel-edit", _} ->
        socket |> Page.Dialog.cancel_edit()

      {"edited-message", %{"dialog_edit" => %{"text" => text}}} ->
        socket |> Page.Dialog.update_edited_message(text)

      {"edit-message", %{"id" => id, "timestamp" => time}} ->
        socket |> Page.Dialog.edit_message({time |> String.to_integer(), id})

      {"download-message", %{"id" => id, "timestamp" => time}} ->
        socket |> Page.Dialog.download_message({time |> String.to_integer(), id})

      {"toggle-messages-select", params} ->
        socket |> Page.Dialog.toggle_messages_select(params)

      {"close-dialog", _} ->
        socket |> Page.Dialog.close()

      {"delete-messages", params} ->
        socket |> Page.Dialog.delete_messages(params)

      {"text-message", %{"dialog" => %{"text" => text}}} ->
        socket |> Page.Dialog.send_text(text)

      {"switch", %{"user-id" => user_id}} ->
        socket |> Page.Dialog.close() |> Page.Dialog.init(user_id)
    end
  end

  #
  # Internal events
  #

  def info(socket, message) do
    case message do
      {:new_dialog_message, glimpse} ->
        socket |> Page.Dialog.show_new(glimpse)

      {:updated_dialog_message, msg_id} ->
        socket |> Page.Dialog.update_message(msg_id, &Index.message_text/1)

      {:deleted_dialog_message, msg_id} ->
        socket |> Page.Dialog.hide_deleted_message(msg_id)
    end
  end
end

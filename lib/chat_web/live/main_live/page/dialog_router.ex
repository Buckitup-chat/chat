defmodule ChatWeb.MainLive.Page.DialogRouter do
  @moduledoc "Route dialog events"

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2]

  alias ChatWeb.MainLive.Layout.Message
  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(%{assigns: %{need_login: true}} = socket, _event) do
    socket |> push_navigate(to: "/")
  end

  def event(socket, event) do
    case event do
      {"message/" <> action, %{"id" => id, "index" => index}} ->
        socket |> route_message_event({action, {index |> String.to_integer(), id}})

      {"message/accept-all-room-invites", _} ->
        socket |> Page.Dialog.accept_all_room_invites()

      {"import-images", _} ->
        socket |> push_event("chat:scroll-down", %{})

      {"import-files", _} ->
        socket
        |> push_event("chat:scroll-down", %{})

      {"cancel-edit", _} ->
        socket |> Page.Dialog.cancel_edit()

      {"edited-message", %{"dialog_edit" => %{"text" => text}}} ->
        socket |> Page.Dialog.update_edited_message(text)

      {"toggle-messages-select", params} ->
        socket |> Page.Dialog.toggle_messages_select(params)

      {"close", _} ->
        socket |> Page.Dialog.close()

      {"delete-messages", params} ->
        socket |> Page.Dialog.delete_messages(params)

      {"download-messages", params} ->
        socket |> Page.Dialog.download_messages(params)

      {"text-message", %{"dialog" => %{"text" => text}}} ->
        socket |> Page.Dialog.send_text(text)

      {"switch", %{"user-id" => user_id}} ->
        socket |> Page.Dialog.close() |> Page.Dialog.init(user_id)
    end
  end

  def route_message_event(socket, {action, msg_id}) do
    case action do
      "accept-room-invite" ->
        socket |> Page.Dialog.accept_room_invite(msg_id, &Message.room_invite_navigation/1)

      "accept-room-invite-and-open-room" ->
        socket |> Page.Dialog.accept_room_invite_and_open_room(msg_id)

      "edit" ->
        socket |> Page.Dialog.edit_message(msg_id)

      "download" ->
        socket |> Page.Dialog.download_message(msg_id)

      "open-image-gallery" ->
        socket |> Page.Dialog.open_image_gallery(msg_id)
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
        socket |> Page.Dialog.update_message(msg_id, &Message.text/1)

      {:deleted_dialog_message, msg_id} ->
        socket |> Page.Dialog.hide_deleted_message(msg_id)

      {:preload_image_gallery, :next} ->
        socket |> Page.Dialog.image_gallery_preload_next()

      {:preload_image_gallery, :prev} ->
        socket |> Page.Dialog.image_gallery_preload_prev()

      {:accept_room_invite, invite} ->
        socket |> Page.Dialog.accept_room_invite(invite, &Message.room_invite_navigation/1)
    end
  end
end

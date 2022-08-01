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
      {"message/" <> action, %{"id" => id, "index" => index}} ->
        socket |> route_message_event({action, {index |> String.to_integer(), id}})

      {"image-gallery/" <> action, _} ->
        socket |> route_image_gallery_event({action})

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

      {"text-message", %{"dialog" => %{"text" => text}}} ->
        socket |> Page.Dialog.send_text(text)

      {"switch", %{"user-id" => user_id}} ->
        socket |> Page.Dialog.close() |> Page.Dialog.init(user_id)
    end
  end

  def route_message_event(socket, {action, msg_id}) do
    case action do
      "accept-room-invite" ->
        socket |> Page.Dialog.accept_room_invite(msg_id)

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

  def route_image_gallery_event(socket, {action}) do
    case action do
      "close" ->
        socket |> Page.Dialog.close_image_gallery()

      "next" ->
        socket |> Page.Dialog.image_gallery_next()

      "prev" ->
        socket |> Page.Dialog.image_gallery_prev()
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

      {:preload_image_gallery, :next} ->
        socket |> Page.Dialog.image_gallery_preload_next()

      {:preload_image_gallery, :prev} ->
        socket |> Page.Dialog.image_gallery_preload_prev()
    end
  end
end

defmodule ChatWeb.MainLive.Page.RoomRouter do
  @moduledoc "Route room events"

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2]

  alias ChatWeb.MainLive.Layout.Message
  alias ChatWeb.MainLive.Modals
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

      {"invite-user", %{"hash" => hash}} ->
        socket |> Page.Room.invite_user(hash |> Base.decode16!(case: :lower))

      {"send-request", %{"room" => hash}} ->
        socket |> Page.Lobby.request_room(hash |> Base.decode16!(case: :lower))

      {"approve-request", %{"hash" => hash}} ->
        socket |> Page.Room.approve_request(hash |> Base.decode16!(case: :lower))

      {"cancel-edit", _} ->
        socket |> Page.Room.cancel_edit()

      {"edited-message", %{"room_edit" => %{"text" => text}}} ->
        socket |> Page.Room.update_edited_message(text)

      {"delete-messages", params} ->
        socket |> Page.Room.delete_messages(params)

      {"download-messages", params} ->
        socket |> Page.Room.download_messages(params)

      {"unlink-messages-modal", _} ->
        socket |> Page.Room.unlink_messages_modal(Modals.UnlinkMessages)

      {"unlink-messages", _} ->
        socket |> Page.Room.unlink_messages(&Message.message_link/1)

      {"toggle-messages-select", params} ->
        socket |> Page.Room.toggle_messages_select(params)

      {"import-images", _} ->
        socket |> push_event("chat:scroll-down", %{})

      {"import-files", _} ->
        socket |> push_event("chat:scroll-down", %{})

      {"close", _} ->
        socket |> Page.Room.close()

      {"text-message", %{"room" => %{"text" => text}}} ->
        socket |> Page.Room.send_text(text)

      {"switch", %{"room" => hash}} ->
        socket |> Page.Room.close() |> Page.Room.init(hash |> Base.decode16!(case: :lower))

      {"sync-stored", data} ->
        socket |> Page.Login.sync_stored_room(data)
    end
  end

  def route_message_event(socket, {action, msg_id}) do
    case action do
      "edit" ->
        socket |> Page.Room.edit_message(msg_id)

      "download" ->
        socket |> Page.Room.download_message(msg_id)

      "link" ->
        socket
        |> Page.Room.link_message(msg_id, &Message.message_link/1)
        |> Page.Room.share_message_link_modal(msg_id, Modals.ShareMessageLink)

      "share-link-modal" ->
        socket |> Page.Room.share_message_link_modal(msg_id, Modals.ShareMessageLink)

      "open-image-gallery" ->
        socket |> Page.Room.open_image_gallery(msg_id)
    end
  end

  def route_live_action(socket) do
    case socket.assigns do
      %{live_action: :room_message_link, room_message_link_hash: hash} ->
        socket |> Page.Room.init_with_linked_message(hash)

      _ ->
        socket
    end
  end

  #
  # Internal events
  #

  def info(socket, message) do
    case message do
      {:new_message, glimpse} ->
        socket |> Page.Room.show_new(glimpse)

      {:updated_message, msg_id} ->
        socket |> Page.Room.update_message(msg_id, &Message.text/1)

      {:deleted_message, msg_id} ->
        socket |> Page.Room.hide_deleted_message(msg_id)

      {:preload_image_gallery, :next} ->
        socket |> Page.Room.image_gallery_preload_next()

      {:preload_image_gallery, :prev} ->
        socket |> Page.Room.image_gallery_preload_prev()
    end
  end
end

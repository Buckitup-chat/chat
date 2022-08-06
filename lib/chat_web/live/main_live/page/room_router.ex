defmodule ChatWeb.MainLive.Page.RoomRouter do
  @moduledoc "Route room events"

  import Phoenix.LiveView, only: [push_event: 3]

  alias ChatWeb.MainLive.Layout.Message
  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"message/" <> action, %{"id" => id, "index" => index}} ->
        socket |> route_message_event({action, {index |> String.to_integer(), id}})

      {"create", %{"new_room" => %{"name" => name, "type" => type}}} ->
        socket |> Page.Lobby.new_room(name, type |> String.to_existing_atom())

      {"invite-user", %{"hash" => hash}} ->
        socket |> Page.Room.invite_user(hash)

      {"send-request", %{"room" => hash}} ->
        socket |> Page.Lobby.request_room(hash)

      {"approve-request", %{"hash" => hash}} ->
        socket |> Page.Room.approve_request(hash)

      {"cancel-edit", _} ->
        socket |> Page.Room.cancel_edit()

      {"edited-message", %{"room_edit" => %{"text" => text}}} ->
        socket |> Page.Room.update_edited_message(text)

      {"delete-messages", params} ->
        socket |> Page.Room.delete_messages(params)

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
        socket |> Page.Room.close() |> Page.Room.init(hash)
    end
  end

  def route_message_event(socket, {action, msg_id}) do
    case action do
      "edit" ->
        socket |> Page.Room.edit_message(msg_id)

      "download" ->
        socket |> Page.Room.download_message(msg_id)
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
        socket |> Page.Room.update_message(msg_id, &Message.message_text/1)

      {:deleted_message, msg_id} ->
        socket |> Page.Room.hide_deleted_message(msg_id)
    end
  end
end

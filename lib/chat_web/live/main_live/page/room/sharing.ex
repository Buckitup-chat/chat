defmodule ChatWeb.MainLive.Page.Room.Sharing do
  @moduledoc """
  Getting room messages out of the room: file and zip downloads, public message links
  (create, cancel all, share-link modal with QR code).

  Part of the `ChatWeb.MainLive.Page.Room` namespace.
  """

  use ChatWeb, :verified_routes

  import ChatWeb.LiveHelpers, only: [open_modal: 3, open_modal: 2, close_modal: 1]
  import ChatWeb.MainLive.Page.Shared, only: [render_to_html_string: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Broker
  alias Chat.Rooms
  alias Chat.Rooms.RoomMessageLinks
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page.Room.Messages

  def download_messages(
        %{assigns: %{my_id: my_id, room: room, room_identity: room_identity, timezone: timezone}} =
          socket,
        %{"messages" => messages}
      ) do
    messages_ids =
      messages
      |> Jason.decode!()
      |> Enum.map(fn %{"id" => message_id, "index" => index} ->
        {String.to_integer(index), message_id}
      end)

    key = Broker.store({:room, {messages_ids, room, my_id, room_identity}, timezone})

    push_event(socket, "chat:redirect", %{url: ~p"/get/zip/#{key}"})
  end

  def download_message(
        %{assigns: %{room_identity: room_identity}} = socket,
        msg_id
      ) do
    msg_id
    |> Rooms.read_message(room_identity)
    |> maybe_redirect_to_file(socket)
  end

  def link_message(
        %{assigns: %{room: room, room_identity: room_identity}} = socket,
        {index, id},
        render_fun
      ) do
    :ok = RoomMessageLinks.create(room, room_identity, {index, id})

    socket
    |> assign(:is_room_linked?, true)
    |> push_event("chat:change", %{
      to: "#room-message-#{id} .link-status",
      content: render_to_html_string(%{linked: true, msg_id: id, msg_index: index}, render_fun)
    })
    |> Messages.forget_current_messages()
  end

  def unlink_messages_modal(socket, component) do
    socket |> open_modal(component)
  end

  def unlink_messages(%{assigns: %{room_identity: room_identity}} = socket, render_fun) do
    RoomMessageLinks.cancel_room_links(room_identity)
    |> Enum.reduce(socket, fn {_, _, index, id}, socket ->
      content = render_to_html_string(%{linked: false, msg_id: id, msg_index: index}, render_fun)

      socket
      |> push_event("chat:change", %{to: "#room-message-#{id} .link-status", content: content})
    end)
    |> assign(:is_room_linked?, false)
    |> close_modal()
  end

  def share_message_link_modal(%{assigns: %{}} = socket, msg_id, component) do
    message_url =
      [ChatWeb.Endpoint.url(), "trusted", "room", RoomMessageLinks.link_hash(msg_id)]
      |> Path.join()

    socket
    |> open_modal(component, %{
      url: message_url,
      encoded_qr_code: Utils.qr_base64_from_url(message_url)
    })
  end

  defp maybe_redirect_to_file(%{type: type, content: json}, socket)
       when type in [:audio, :file, :image, :video] do
    {file_id, secret} = StorageId.from_json(json)
    file_id = Base.encode16(file_id, case: :lower)
    params = %{a: Base.url_encode64(secret)}

    url =
      case type do
        :image ->
          params = Map.put(params, :download, true)
          ~p"/get/image/#{file_id}?#{params}"

        _ ->
          ~p"/get/file/#{file_id}?#{params}"
      end

    push_event(socket, "chat:redirect", %{url: url})
  end

  defp maybe_redirect_to_file(_message, socket), do: socket
end

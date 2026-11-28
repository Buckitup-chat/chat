defmodule ChatWeb.MainLive.Page.Dialog.Sharing do
  @moduledoc """
  Getting dialog messages out of the dialog: file and zip downloads, the chat link
  modal with QR code.

  Part of the `ChatWeb.MainLive.Page.Dialog` namespace.
  """

  use ChatWeb, :verified_routes

  import ChatWeb.LiveHelpers, only: [open_modal: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Broker
  alias Chat.Dialogs
  alias Chat.Utils
  alias Chat.Utils.StorageId

  def download_message(
        %{assigns: %{me: me, dialog: dialog}} = socket,
        msg_id
      ) do
    dialog
    |> Dialogs.read_message(msg_id, me)
    |> maybe_redirect_to_file(socket)
  end

  def download_messages(
        %{assigns: %{dialog: dialog, me: me, peer: peer, timezone: timezone}} = socket,
        %{"messages" => messages}
      ) do
    messages_ids =
      messages
      |> Jason.decode!()
      |> Enum.map(fn %{"id" => message_id, "index" => index} ->
        {String.to_integer(index), message_id}
      end)

    key = Broker.store({:dialog, {dialog, messages_ids, me, peer}, timezone})

    push_event(socket, "chat:redirect", %{url: path(socket, ~p"/get/zip/#{key}")})
  end

  def show_link_modal(%{assigns: %{}} = socket, hash, component) do
    chat_url = [ChatWeb.Endpoint.url(), "trusted", "chat", hash] |> Path.join()

    socket
    |> open_modal(component, %{url: chat_url, encoded_qr_code: Utils.qr_base64_from_url(chat_url)})
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

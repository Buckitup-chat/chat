defmodule ChatWeb.MainLive.Page.ImageGallery.ProxySlide do
  @moduledoc """
  Opening the image gallery on a proxy dialog: the image message is fetched from the
  proxied server in a task, deciphered, and delivered back to the gallery component
  with a `:current_delivered` update.

  Part of the `ChatWeb.MainLive.Page.ImageGallery` namespace.
  """

  alias Chat.Dialogs.DialogMessaging
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page.ImageGallery
  alias ChatWeb.Utils
  alias Proxy

  def open(socket, %{incoming_msg_id: msg_id, dialog: dialog, me: me, server: server}) do
    index = msg_id["index"] |> String.to_integer()

    action = fn page_pid ->
      message =
        Proxy.get_dialog_message(
          server,
          dialog,
          index,
          msg_id["id"]
        )
        |> decypher_file_message({me, dialog, index, server})

      current_slide = %{url: message.file_url, id: msg_id["id"], index: index}

      Phoenix.LiveView.send_update(page_pid, ImageGallery,
        id: "imageGallery",
        action: :current_delivered,
        current: current_slide,
        list: [current_slide],
        is_open?: true
      )
    end

    spawn_task(action)

    socket
  end

  def decypher_file_message(message, {me, dialog, index, server}) do
    [message]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn msg ->
      {index, msg} |> DialogMessaging.read(me, dialog)
    end)
    |> Enum.filter(& &1)
    |> Enum.reverse()
    |> Enum.map(fn
      %{type: type, content: json} = msg when type in [:image, :audio, :file, :video] ->
        {id, secret} = json |> StorageId.from_json()

        file_info =
          Proxy.get_file_info(server, id)
          |> Enum.map(&Enigma.decipher(&1, secret))

        msg
        |> Map.from_struct()
        |> Map.put(:file_info, file_info)
        |> Map.put(:file_url, Utils.get_proxied_file_url(server, id, secret))
    end)
    |> List.first()
  end

  defp spawn_task(action) do
    pid = self()

    Task.start(fn -> action.(pid) end)
  end
end

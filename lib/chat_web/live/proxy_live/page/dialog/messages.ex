defmodule ChatWeb.ProxyLive.Page.Dialog.Messages do
  @moduledoc """
  The proxy dialog message list: loading pages of messages from the proxied server,
  showing a new message, select mode.

  Part of the `ChatWeb.ProxyLive.Page.Dialog` namespace.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import Tools.SocketPrivate

  alias Chat.Dialogs
  alias Chat.Dialogs.DialogMessaging
  alias Chat.Utils.StorageId
  alias ChatWeb.State.ActorState
  alias ChatWeb.Utils, as: WebUtils
  alias Proxy

  @per_page 15

  def add_loaded_messages(socket, messages, amount, dialog) do
    if dialog == socket.assigns.dialog do
      new_messages = Enum.take(messages, -amount)

      last_index =
        case new_messages do
          [first | _] when is_map(first) -> Map.get(first, :index)
          _ -> nil
        end

      socket
      |> assign(:messages, new_messages)
      |> assign(:has_more_messages, Enum.count(messages) > amount)
      |> assign(:last_load_timestamp, last_index)
    else
      socket
    end
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{input_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    server = socket |> get_private(:server)

    messages =
      [DialogMessaging.read(new_message, me, dialog)]
      |> Enum.reject(&is_nil/1)
      |> Chat.Messaging.preload_content(&Proxy.get_data_by_keys(server, &1))
      |> ensure_proxy_urls(server)

    socket
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
    |> push_event("chat:scroll-down", %{})
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{input_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :plain)
  end

  def assign_messages(socket, per_page \\ @per_page)

  def assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket

  def assign_messages(
        %{assigns: %{dialog: dialog, last_load_timestamp: max_index}} = socket,
        per_page
      ) do
    server = socket |> get_private(:server)
    my_identity = ActorState.my_identity(socket)
    pid = self()

    Task.start(fn ->
      peer = Dialogs.peer(dialog, my_identity)
      Proxy.find_or_create_dialog(server, my_identity, peer)

      messages =
        Proxy.get_dialog_messages(server, dialog, max_index, per_page + 1)
        |> Enum.map(fn {{:dialog_message, _, index, _}, msg} ->
          {index, msg} |> DialogMessaging.read(my_identity, dialog)
        end)
        |> Enum.filter(& &1)
        |> Enum.reverse()
        |> Chat.Messaging.preload_content(&Proxy.get_data_by_keys(server, &1))
        |> ensure_proxy_urls(server)

      send(pid, {:dialog, {:loaded_messages, messages, per_page, dialog}})
    end)

    socket
    |> assign(:messages, [])
  end

  def forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end

  defp ensure_proxy_urls(messages, server) do
    Enum.map(messages, fn
      %{type: type, content: json} = msg when type in [:image, :audio, :file, :video] ->
        {id, secret} = json |> StorageId.from_json()

        msg
        |> Map.put(:file_url, WebUtils.get_proxied_file_url(server, id, secret))

      simple_message ->
        simple_message
    end)
  end
end

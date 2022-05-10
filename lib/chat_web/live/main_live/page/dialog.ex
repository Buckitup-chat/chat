defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc "Dialog page"
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Dialogs
  alias Chat.Log
  alias Chat.User

  @per_page 15

  def init(%{assigns: %{my_id: my_id}} = socket), do: init(socket, my_id)

  def init(%{assigns: %{me: me}} = socket, user_id) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)
    IO.inspect "init mount"
    
    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())
    Log.open_direct(me, peer)

    socket
    |> assign(:page, 0)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:has_more_messages, true)
    |> assign_messages()
    |> assign(:message_update_mode, :replace)
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    IO.inspect "hh"
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
  end

  def send_text(%{assigns: %{dialog: dialog, me: me}} = socket, text) do
    new_message =
      dialog
      |> Dialogs.add_text(me, text)

    PubSub.broadcast!(
      Chat.PubSub,
      dialog |> dialog_topic(),
      {:new_dialog_message, new_message}
    )

    Log.message_direct(me, Dialogs.peer(dialog, me))

    socket
  end

  def send_image(%{assigns: %{dialog: dialog, me: me}} = socket) do
    new_message =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{path: path}, entry ->
          data = {File.read!(path), entry.client_type}
          {:ok, Dialogs.add_image(dialog, me, data)}
        end
      )
      |> Enum.at(0)

    PubSub.broadcast!(
      Chat.PubSub,
      dialog |> dialog_topic(),
      {:new_dialog_message, new_message}
    )

    Log.message_direct(me, Dialogs.peer(dialog, me))

    socket
  end

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    IO.inspect(new_message)

    socket
    |> assign(:messages, [Dialogs.read_message(dialog, new_message, me)])
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
  end

  def close(%{assigns: %{dialog: nil}} = socket), do: socket

  def close(%{assigns: %{dialog: dialog}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
  end

  defp dialog_topic(%Dialogs.Dialog{} = dialog) do
    dialog
    |> Dialogs.key()
    |> then(&"dialog:#{&1}")
  end

  defp assign_messages(socket, per_page \\ @per_page)
  
  defp assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket
  
  defp assign_messages(%{assigns: %{page: 0, dialog: dialog, me: me}} = socket, per_page) do
    messages = Dialogs.read(dialog, me, {nil, 0}, per_page + 1)
    
    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
  end

  defp assign_messages(%{assigns: %{dialog: dialog, me: me, messages: messages}} = socket, per_page) do
    before_message = List.first(messages) 
    messages = Dialogs.read(dialog, me, {before_message.timestamp, 0}, per_page + 1)
    
    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
  end
end

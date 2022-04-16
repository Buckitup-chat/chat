defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc "Dialog page"
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Dialogs
  alias Chat.Log
  alias Chat.User

  def init(%{assigns: %{me: me}} = socket, user_id) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)
    messages = dialog |> Dialogs.read(me)

    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())
    Log.open_direct(me, peer)

    socket
    |> assign(:mode, :dialog)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :replace)
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
    socket
    |> assign(:messages, [Dialogs.read_message(dialog, new_message, me)])
    |> assign(:message_update_mode, :append)
  end

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
end

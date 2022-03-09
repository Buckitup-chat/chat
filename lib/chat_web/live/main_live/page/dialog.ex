defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc "Dialog page"
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Dialogs
  alias Chat.User
  alias Chat.Utils

  def init(%{assigns: %{me: me}} = socket, user_id) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)
    messages = dialog |> Dialogs.read(me)

    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:mode, :dialog)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :replace)
  end

  def send_text(%{assigns: %{dialog: dialog, me: me}} = socket, text) do
    updated_dialog =
      dialog
      |> Dialogs.add_text(me, text)
      |> tap(&Dialogs.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_dialog |> dialog_topic(),
      {:new_dialog_message, updated_dialog |> Dialogs.glimpse()}
    )

    socket
    |> assign(:dialog, updated_dialog)
  end

  def send_image(%{assigns: %{dialog: dialog, me: me}} = socket) do
    updated_dialog =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{path: path}, entry ->
          data = {File.read!(path), entry.client_type}
          {:ok, Dialogs.add_image(dialog, me, data)}
        end
      )
      |> Enum.at(0)
      |> tap(&Dialogs.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_dialog |> dialog_topic(),
      {:new_dialog_message, updated_dialog |> Dialogs.glimpse()}
    )

    socket
    |> assign(:dialog, updated_dialog)
  end

  def show_new(%{assigns: %{me: me}} = socket, glimpse) do
    socket
    |> assign(:messages, glimpse |> Dialogs.read(me))
    |> assign(:message_update_mode, :append)
  end

  def close(%{assigns: %{dialog: dialog}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
  end

  defp dialog_topic(%Dialogs.Dialog{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join("---")
    |> then(&"dialog:#{&1}")
  end
end

defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc "Dialog page"
  import ChatWeb.MainLive.Page.Shared
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entry: 3, push_event: 3]

  use Phoenix.Component

  alias Phoenix.PubSub

  alias Chat.Dialogs
  alias Chat.Log
  alias Chat.Memo
  alias Chat.User
  alias Chat.Utils.StorageId
  alias ChatWeb.Router.Helpers, as: Routes

  @per_page 15

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:dialog, nil)
    |> assign(:peer, nil)
  end

  def init(%{assigns: %{me: me}} = socket, user_id) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)

    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())
    Log.open_direct(me, peer)

    socket
    |> assign(:page, 0)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:dialog_mode, :plain)
    |> assign(:has_more_messages, true)
    |> assign(:last_load_timestamp, nil)
    |> assign(:message_update_mode, :replace)
    |> assign_messages()
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{dialog_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def send_text(%{assigns: %{dialog: dialog, me: me}} = socket, text) do
    if is_memo?(text) do
      dialog |> Dialogs.add_memo(me, text)
    else
      dialog |> Dialogs.add_text(me, text)
    end
    |> broadcast_new_message(dialog, me)

    socket
  end

  def send_file(%{assigns: %{dialog: dialog, me: me}} = socket, entry) do
    consume_uploaded_entry(
      socket,
      entry,
      fn %{path: path} ->
        data = [
          File.read!(path),
          entry.client_type |> mime_type(),
          entry.client_name,
          entry.client_size |> format_size()
        ]

        {:ok, Dialogs.add_file(dialog, me, data)}
      end
    )
    |> broadcast_new_message(dialog, me)

    socket
  end

  def send_image(%{assigns: %{dialog: dialog, me: me}} = socket, entry) do
    consume_uploaded_entry(
      socket,
      entry,
      fn %{path: path} ->
        data = [File.read!(path), entry.client_type]
        {:ok, Dialogs.add_image(dialog, me, data)}
      end
    )
    |> broadcast_new_message(dialog, me)

    socket
  end

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    socket
    |> assign(:messages, [Dialogs.read_message(dialog, new_message, me)])
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
  end

  def edit_message(%{assigns: %{me: me, dialog: dialog}} = socket, msg_id) do
    content =
      Dialogs.read_message(dialog, msg_id, me)
      |> then(fn
        %{type: :text, content: text} ->
          text

        %{type: :memo, content: json} ->
          json |> StorageId.from_json() |> Memo.get()
      end)

    socket
    |> assign(:dialog_mode, :edit)
    |> assign(:edit_content, content)
    |> assign(:edit_message_id, msg_id)
    |> forget_current_messages()
    |> push_event("chat:focus", %{to: "#dialog-edit-input"})
  end

  def update_edited_message(
        %{assigns: %{dialog: dialog, me: me, edit_message_id: msg_id}} = socket,
        text
      ) do
    content = if is_memo?(text), do: {:memo, text}, else: text

    Dialogs.update(dialog, me, msg_id, content)
    broadcast_message_updated(msg_id, dialog, me)

    socket
    |> cancel_edit()
  end

  def update_message(
        %{assigns: %{me: me, dialog: dialog}} = socket,
        {_time, id} = msg_id,
        render_fun
      ) do
    content =
      Dialogs.read_message(dialog, msg_id, me)
      |> then(&%{msg: &1})
      |> render_to_html_string(render_fun)

    socket
    |> forget_current_messages()
    |> push_event("chat:change", %{to: "#dialog-message-#{id} .x-content", content: content})
  end

  def cancel_edit(socket) do
    socket
    |> assign(:dialog_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_message(%{assigns: %{me: me, dialog: dialog}} = socket, {time, msg_id}) do
    Dialogs.delete(dialog, me, {time, msg_id})
    broadcast_message_deleted(msg_id, dialog, me)

    socket
  end

  def delete_messages(%{assigns: %{me: me, dialog: dialog}} = socket, %{"messages" => messages}) do
    messages
    |> Jason.decode!()
    |> Enum.map(fn %{"id" => msg_id, "timestamp" => time} ->
      Dialogs.delete(dialog, me, {String.to_integer(time), msg_id})
      broadcast_message_deleted(msg_id, dialog, me)
    end)

    socket
    |> assign(:dialog_mode, :plain)
  end

  def hide_deleted_message(socket, id) do
    socket
    |> forget_current_messages()
    |> push_event("chat:toggle", %{to: "#message-block-#{id}", class: "hidden"})
  end

  def download_message(
        %{assigns: %{me: me, dialog: dialog}} = socket,
        msg_id
      ) do
    dialog
    |> Dialogs.read_message(msg_id, me)
    |> case do
      %{type: :file, content: json} ->
        {file_id, secret} = json |> StorageId.from_json()

        socket
        |> push_event("chat:redirect", %{
          url: Routes.file_url(socket, :file, file_id, a: secret |> Base.url_encode64())
        })

      %{type: :image, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        socket
        |> push_event("chat:redirect", %{
          url:
            Routes.file_url(socket, :image, id, a: secret |> Base.url_encode64(), download: true)
        })

      _ ->
        socket
    end
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:dialog_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{dialog_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:dialog_mode, :plain)
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

  defp assign_messages(
         %{assigns: %{dialog: dialog, me: me, last_load_timestamp: timestamp}} = socket,
         per_page
       ) do
    messages = Dialogs.read(dialog, me, {timestamp, 0}, per_page + 1)

    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(messages))
  end

  defp broadcast_new_message(message, dialog, me) do
    {:new_dialog_message, message}
    |> dialog_broadcast(dialog)

    Log.message_direct(me, Dialogs.peer(dialog, me))
  end

  defp broadcast_message_updated(message_id, dialog, me) do
    {:updated_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.update_message_direct(me, Dialogs.peer(dialog, me))
  end

  defp broadcast_message_deleted(message_id, dialog, me) do
    {:deleted_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.delete_message_direct(me, Dialogs.peer(dialog, me))
  end

  defp dialog_broadcast(message, dialog) do
    PubSub.broadcast!(
      Chat.PubSub,
      dialog |> dialog_topic(),
      message
    )
  end

  defp set_messages_timestamp([]), do: nil
  defp set_messages_timestamp([message | _]), do: message.timestamp

  defp forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end
end

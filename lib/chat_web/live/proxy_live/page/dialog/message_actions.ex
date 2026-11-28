defmodule ChatWeb.ProxyLive.Page.Dialog.MessageActions do
  @moduledoc """
  Changing proxy dialog messages: sending text (to the proxied server) and the
  send/file/edit/delete/re-render actions copied from the main dialog page.

  Part of the `ChatWeb.ProxyLive.Page.Dialog` namespace.
  """

  import ChatWeb.MainLive.Page.Shared, only: [render_to_html_string: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3]
  import Tools.SocketPrivate

  alias Chat.ChunkedFiles
  alias Chat.Content.Memo
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Upload.UploadMetadata
  alias Chat.Utils.StorageId
  alias ChatWeb.ProxyLive.Page.Dialog.Broadcast
  alias ChatWeb.ProxyLive.Page.Dialog.Messages, as: MessageList
  alias Proxy

  def send_text_message(socket, params) do
    server = socket |> get_private(:server)
    %{dialog: dialog, me: me} = socket.assigns
    %{"dialog" => %{"text" => text}} = params
    trimmed_text = String.trim(text)

    if trimmed_text != "" do
      time = Chat.TimeKeeper.now_unix()

      Task.start(fn ->
        %Messages.Text{text: text, timestamp: time}
        |> Chat.SignedParcel.wrap_dialog_message(dialog, me)
        |> Proxy.save_parcel(server, me)
      end)
    end

    socket
  end

  def send_text(
        %{assigns: %{dialog: dialog, me: me, monotonic_offset: time_offset}} = socket,
        text
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    text
    |> String.trim()
    |> case do
      "" ->
        nil

      text ->
        %Messages.Text{text: text, timestamp: time}
        |> Dialogs.add_new_message(me, dialog)
        |> MemoIndex.add(dialog, me)
        |> Broadcast.broadcast_new_message(dialog, me, time)
    end

    socket
  end

  def send_file(
        %{assigns: %{me: me, monotonic_offset: time_offset}} = socket,
        entry,
        %UploadMetadata{credentials: {chunk_key, chunk_secret}, destination: %{dialog: dialog}} =
          _metadata
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    message =
      consume_uploaded_entry(
        socket,
        entry,
        fn _ ->
          Messages.File.new(
            entry,
            chunk_key,
            ChunkedFiles.decrypt_secret(chunk_secret, me),
            time
          )
          |> Dialogs.add_new_message(me, dialog)
          |> then(&{:ok, &1})
        end
      )

    {_index, msg} = message

    FileIndex.save(chunk_key, dialog.a_key, msg.id, chunk_secret)
    FileIndex.save(chunk_key, dialog.b_key, msg.id, chunk_secret)

    message
    |> Dialogs.on_saved(dialog, fn ->
      Broadcast.broadcast_new_message(message, dialog, me, time)
    end)

    socket
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
    |> assign(:input_mode, :edit)
    |> assign(:edit_content, content)
    |> assign(:edit_message_id, msg_id)
    |> MessageList.forget_current_messages()
    |> push_event("chat:focus", %{to: "#dialog-edit-input"})
  end

  def update_edited_message(
        %{
          assigns: %{
            dialog: dialog,
            me: me,
            edit_message_id: msg_id,
            monotonic_offset: time_offset
          }
        } = socket,
        text
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    text
    |> Messages.Text.new(time)
    |> Dialogs.update_message(msg_id, me, dialog)
    |> MemoIndex.add(dialog, me)
    |> Dialogs.on_saved(dialog, fn ->
      Broadcast.broadcast_message_updated(msg_id, dialog, me, time)
    end)

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
    |> MessageList.forget_current_messages()
    |> push_event("chat:change", %{to: "#dialog-message-#{id} .x-content", content: content})
  end

  def cancel_edit(socket) do
    socket
    |> assign(:input_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_messages(
        %{assigns: %{me: me, dialog: dialog, monotonic_offset: time_offset}} = socket,
        %{
          "messages" => messages
        }
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    messages
    |> Jason.decode!()
    |> Enum.each(fn %{"id" => msg_id, "index" => index} ->
      Dialogs.delete(dialog, me, {String.to_integer(index), msg_id})
      Broadcast.broadcast_message_deleted(msg_id, dialog, me, time)
    end)

    socket
    |> assign(:input_mode, :plain)
  end

  def hide_deleted_message(socket, id) do
    socket
    |> MessageList.forget_current_messages()
    |> push_event("chat:toggle", %{to: "#message-block-#{id}", class: "hidden"})
  end
end

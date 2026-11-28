defmodule ChatWeb.MainLive.Page.Room.MessageActions do
  @moduledoc """
  Changing room messages: sending text and files, editing (`:input_mode` `:edit`), deleting,
  and re-rendering a single updated or deleted message. Each change is broadcast through
  `ChatWeb.MainLive.Page.Room.Broadcast`.

  Part of the `ChatWeb.MainLive.Page.Room` namespace; the list itself lives in
  `ChatWeb.MainLive.Page.Room.Messages` (aliased `MessageList` here).
  """

  require Logger

  import ChatWeb.MainLive.Page.Shared, only: [render_to_html_string: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3]

  alias Chat.ChunkedFiles
  alias Chat.Content.Memo
  alias Chat.FileIndex
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Upload.UploadMetadata
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page.Room.Broadcast
  alias ChatWeb.MainLive.Page.Room.Messages, as: MessageList

  def send_text(
        %{assigns: %{room: room, me: me, room_map: rooms, monotonic_offset: time_offset}} =
          socket,
        text
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    case String.trim(text) do
      "" ->
        nil

      content ->
        %Messages.Text{text: content, timestamp: time}
        |> Chat.SignedParcel.wrap_room_message(rooms[room.pub_key], me)
        |> Chat.store_parcel()
        |> Chat.run_when_parcel_stored(fn parcel ->
          # Extract and broadcast the message
          {index, message} = Chat.Rooms.parcel_to_indexed_message(parcel, rooms[room.pub_key])
          Broadcast.broadcast_new_message({index, message}, room.pub_key, me, time)
        end)
    end

    socket
  end

  def send_file(
        %{assigns: %{me: me, monotonic_offset: time_offset, room_map: rooms}} = socket,
        entry,
        %UploadMetadata{
          credentials: {chunk_key, chunk_secret},
          destination: %{pub_key: text_pub_key}
        } = _metadata
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    pub_key = text_pub_key |> Base.decode16!(case: :lower)

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
          |> Rooms.add_new_message(me, rooms[pub_key])
          |> then(&{:ok, &1})
        end
      )

    {_index, msg} = message

    FileIndex.save(chunk_key, pub_key, msg.id, chunk_secret)

    Rooms.on_saved(message, pub_key, fn ->
      Broadcast.broadcast_new_message(message, pub_key, me, time)
    end)

    socket
  end

  def edit_message(
        %{assigns: %{room_identity: room_identity}} = socket,
        msg_id
      ) do
    content =
      Rooms.read_message(msg_id, room_identity)
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
    |> push_event("chat:focus", %{to: "#room-edit-input"})
  end

  def update_edited_message(
        %{
          assigns: %{
            room_identity: room_identity,
            room: room,
            me: me,
            edit_message_id: msg_id,
            monotonic_offset: time_offset
          }
        } = socket,
        text
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    text
    |> Messages.Text.new(0)
    |> Rooms.update_message(msg_id, me, room_identity)
    |> MemoIndex.add(room, room_identity)

    Broadcast.broadcast_message_updated(msg_id, room.pub_key, me, time)

    socket
    |> cancel_edit()
  end

  def update_message(
        %{assigns: %{room_identity: room_identity, my_id: my_id}} = socket,
        {_time, id} = msg_id,
        render_fun
      ) do
    message = Rooms.read_message(msg_id, room_identity)
    [loaded_message] = Chat.Messaging.preload_content([message])
    content = render_to_html_string(%{msg: loaded_message, my_id: my_id}, render_fun)

    socket
    |> MessageList.forget_current_messages()
    |> push_event("chat:change", %{to: "#room-message-#{id} .x-content", content: content})
  end

  def update_message(socket, msg_id, _) do
    identity = socket.assigns[:room_identity] |> inspect()

    Logger.warning([
      "Cannot show upated message in room. ",
      "msg_id: ",
      inspect(msg_id),
      " room: ",
      identity
    ])

    socket
  end

  def cancel_edit(socket) do
    socket
    |> assign(:input_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_messages(
        %{
          assigns: %{
            me: me,
            room_identity: room_identity,
            room: room,
            monotonic_offset: time_offset
          }
        } = socket,
        %{
          "messages" => messages
        }
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    messages
    |> Jason.decode!()
    |> Enum.each(fn %{"id" => msg_id, "index" => index} ->
      Rooms.delete_message({String.to_integer(index), msg_id}, room_identity, me)
      Broadcast.broadcast_deleted_message(msg_id, room.pub_key, me, time)
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

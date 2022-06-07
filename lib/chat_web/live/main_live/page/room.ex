defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"
  import ChatWeb.MainLive.Page.Shared
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3, push_event: 3]

  alias Phoenix.PubSub

  alias Chat.Identity
  alias Chat.Log
  alias Chat.Memo
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.Router.Helpers, as: Routes

  @per_page 15

  def init(socket), do: socket |> assign(:room, nil)

  def init(%{assigns: %{rooms: rooms, me: me}} = socket, room_hash) do
    room = Rooms.get(room_hash)

    room_identity =
      rooms
      |> Enum.find(&(room_hash == &1 |> Identity.pub_key() |> Utils.hash()))

    PubSub.subscribe(Chat.PubSub, room |> room_topic())
    Log.visit_room(me, room_identity)

    socket
    |> assign(:page, 0)
    |> assign(:lobby_mode, :rooms)
    |> assign(:room_mode, :plain)
    |> assign(:room, room)
    |> assign(:room_identity, room_identity)
    |> assign(:last_load_timestamp, nil)
    |> assign(:has_more_messages, true)
    |> assign(:message_update_mode, :replace)
    |> assign_messages()
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{room_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#room-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def send_text(%{assigns: %{room: room, me: me, room_identity: room_identity}} = socket, text) do
    if is_memo?(text) do
      room_identity |> Rooms.add_memo(me, text)
    else
      room |> Rooms.add_text(me, text)
    end
    |> broadcast_new_message(room, me)

    socket
  end

  def send_file(%{assigns: %{me: me, room: room}} = socket) do
    consume_uploaded_entries(
      socket,
      :room_file,
      fn %{path: path}, entry ->
        data = [
          File.read!(path),
          entry.client_type |> mime_type(),
          entry.client_name,
          entry.client_size |> format_size()
        ]

        {:ok, Rooms.add_file(room, me, data)}
      end
    )
    |> Enum.at(0)
    |> broadcast_new_message(room, me)

    socket
  end

  def send_image(%{assigns: %{me: me, room: room}} = socket) do
    consume_uploaded_entries(
      socket,
      :room_image,
      fn %{path: path}, entry ->
        data = [File.read!(path), entry.client_type]
        {:ok, Rooms.add_image(room, me, data)}
      end
    )
    |> Enum.at(0)
    |> broadcast_new_message(room, me)

    socket
  end

  def show_new(
        %{assigns: %{room_identity: identity}} = socket,
        %{author_hash: hash, encrypted: {data, sign}} = new_message
      ) do
    if Utils.is_signed_by?(sign, data, User.by_id(hash)) do
      socket
      |> assign(:page, 0)
      |> assign(:messages, [new_message |> Rooms.read_message(identity)])
      |> assign(:message_update_mode, :append)
    else
      socket
    end
  end

  def edit_message(
        %{assigns: %{room_identity: room_identity}} = socket,
        msg_id
      ) do
    content =
      Rooms.read_message(msg_id, room_identity, &User.id_map_builder/1)
      |> then(fn
        %{type: :text, content: text} ->
          text

        %{type: :memo, content: json} ->
          json |> StorageId.from_json() |> Memo.get()
      end)

    socket
    |> assign(:room_mode, :edit)
    |> assign(:edit_content, content)
    |> assign(:edit_message_id, msg_id)
    |> forget_current_messages()
    |> push_event("chat:focus", %{to: "#room-edit-input"})
  end

  def update_edited_message(
        %{assigns: %{room_identity: room_identity, room: room, me: me, edit_message_id: msg_id}} =
          socket,
        text
      ) do
    content = if is_memo?(text), do: {:memo, text}, else: text

    Rooms.update_message(msg_id, content, room_identity, me)
    broadcast_message_updated(msg_id, room, me)

    socket
    |> cancel_edit()
  end

  def update_message(
        %{assigns: %{room_identity: room_identity, my_id: my_id}} = socket,
        {_time, id} = msg_id,
        render_fun
      ) do
    content =
      Rooms.read_message(msg_id, room_identity, &User.id_map_builder/1)
      |> then(&%{msg: &1, my_id: my_id})
      |> render_to_html_string(render_fun)

    socket
    |> forget_current_messages()
    |> push_event("chat:change", %{to: "#room-message-#{id} .x-content", content: content})
  end

  def cancel_edit(socket) do
    socket
    |> assign(:room_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_message(
        %{assigns: %{me: me, room_identity: room_identity, room: room}} = socket,
        {time, msg_id}
      ) do
    Rooms.delete_message({time, msg_id}, room_identity, me)
    broadcast_deleted_message(msg_id, room, me)

    socket
  end

  def delete_messages(%{assigns: %{me: me, room_identity: room_identity, room: room}} = socket, %{
        "messages" => messages
      }) do
    messages
    |> Jason.decode!()
    |> Enum.map(fn %{"id" => msg_id, "timestamp" => time} ->
      Rooms.delete_message({String.to_integer(time), msg_id}, room_identity, me)
      broadcast_deleted_message(msg_id, room, me)
    end)

    socket
    |> assign(:room_mode, :plain)
  end

  def hide_deleted_message(socket, id) do
    socket
    |> forget_current_messages()
    |> push_event("chat:toggle", %{to: "#message-block-#{id}", class: "hidden"})
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket

  def close(%{assigns: %{room: room}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, room |> room_topic())

    socket
    |> assign(:room, nil)
    |> assign(:edit_room, nil)
    |> assign(:room_identity, nil)
    |> assign(:messages, nil)
    |> assign(:message_update_mode, nil)
  end

  def download_message(
        %{assigns: %{room_identity: room_identity}} = socket,
        msg_id
      ) do
    Rooms.read_message(msg_id, room_identity, &User.id_map_builder/1)
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

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on", "id" => _} = params) do
    socket
    |> forget_current_messages()
    |> assign(:room_mode, :select)
    |> push_event("chat:toggle", %{to: "#room-messages", class: "selectMode"})
    |> push_event("chat:select-message", params)
  end

  def toggle_messages_select(%{assigns: %{room_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:room_mode, :plain)
  end

  def select_message(
        %{assigns: %{room_mode: :select}} = socket,
        %{"id" => _id, "type" => "room"} = params
      ) do
    socket
    |> push_event("chat:select-message", params)
  end

  def select_message(%{assigns: %{}} = socket, _), do: socket

  defp room_topic(%Rooms.Room{pub_key: key}) do
    key
    |> Utils.hash()
    |> then(&"room:#{&1}")
  end

  defp assign_messages(socket, per_page \\ @per_page)

  defp assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket

  defp assign_messages(
         %{
           assigns: %{
             room: room,
             room_identity: identity,
             last_load_timestamp: timestamp
           }
         } = socket,
         per_page
       ) do
    messages = Rooms.read(room, identity, &User.id_map_builder/1, {timestamp, 0}, per_page + 1)

    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(messages))
  end

  defp broadcast_message_updated(msg_id, room, me) do
    {:updated_message, msg_id}
    |> room_broadcast(room)

    Log.update_room_message(me, room.pub_key)
  end

  defp broadcast_new_message(message, room, me) do
    {:new_message, message}
    |> room_broadcast(room)

    Log.message_room(me, room.pub_key)
  end

  defp broadcast_deleted_message(msg_id, room, me) do
    {:deleted_message, msg_id}
    |> room_broadcast(room)

    Log.delete_room_message(me, room.pub_key)
  end

  defp room_broadcast(message, room) do
    PubSub.broadcast!(
      Chat.PubSub,
      room |> room_topic(),
      {:room, message}
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

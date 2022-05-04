defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"
  import ChatWeb.MainLive.Page.Shared
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  def init(%{assigns: %{rooms: rooms, me: me}} = socket, room_hash) do
    room = Rooms.get(room_hash)

    room_identity =
      rooms
      |> Enum.find(&(room_hash == &1 |> Identity.pub_key() |> Utils.hash()))

    messages = room |> Rooms.read(room_identity, &User.id_map_builder/1)

    PubSub.subscribe(Chat.PubSub, room |> room_topic())

    Log.visit_room(me, room_identity)

    socket
    |> assign(:mode, :room)
    |> assign(:room, room)
    |> assign(:room_identity, room_identity)
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :replace)
  end

  def send_text(%{assigns: %{room: room, me: me}} = socket, text) do
    if String.length(text) > 150 do
      room |> Rooms.add_memo(me, text)
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
      |> assign(:messages, [new_message |> Rooms.read_message(identity)])
      |> assign(:message_update_mode, :append)
    else
      socket
    end
  end

  def delete_message(
        %{assigns: %{me: me, room_identity: room_identity, room: room}} = socket,
        {time, msg_id}
      ) do
    Rooms.delete_message({time, msg_id}, room_identity, me)
    broadcast_deleted_message(msg_id, room, me)

    socket
  end

  def close(%{assigns: %{room: room}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, room |> room_topic())

    socket
    |> assign(:room, nil)
    |> assign(:room_identity, nil)
    |> assign(:messages, nil)
    |> assign(:message_update_mode, nil)
  end

  defp room_topic(%Rooms.Room{pub_key: key}) do
    key
    |> Utils.hash()
    |> then(&"room:#{&1}")
  end

  defp broadcast_new_message(message, room, me) do
    {:new_room_message, message}
    |> room_broadcast(room)

    Log.message_room(me, room.pub_key)
  end

  defp broadcast_deleted_message(msg_id, room, me) do
    {:deleted_room_message, msg_id}
    |> room_broadcast(room)

    Log.delete_room_message(me, room.pub_key)
  end

  defp room_broadcast(message, room) do
    PubSub.broadcast!(
      Chat.PubSub,
      room |> room_topic(),
      message
    )
  end
end

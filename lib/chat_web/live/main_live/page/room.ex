defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Utils

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
    |> assign(:room, room)
    |> assign(:room_identity, room_identity)
    |> assign(:has_more_messages, true)
    |> assign_messages()
    |> assign(:message_update_mode, :replace)
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
  end

  def send_text(%{assigns: %{room: room, me: me}} = socket, text) do
    new_message =
      room
      |> Rooms.add_text(me, text)

    PubSub.broadcast!(
      Chat.PubSub,
      room |> room_topic(),
      {:new_room_message, new_message}
    )

    Log.message_room(me, room.pub_key)

    socket
  end

  def send_image(%{assigns: %{me: me, room: room}} = socket) do
    new_message =
      consume_uploaded_entries(
        socket,
        :room_image,
        fn %{path: path}, entry ->
          data = {File.read!(path), entry.client_type}
          {:ok, Rooms.add_image(room, me, data)}
        end
      )
      |> Enum.at(0)

    PubSub.broadcast!(
      Chat.PubSub,
      room |> room_topic(),
      {:new_room_message, new_message}
    )

    Log.message_room(me, room.pub_key)

    socket
  end

  def show_new(%{assigns: %{room_identity: identity}} = socket, new_message) do
    socket
    |> assign(:messages, [new_message |> Rooms.read_message(identity)])
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket

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

  defp assign_messages(socket, per_page \\ @per_page)
  
  defp assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket
  
  defp assign_messages(%{assigns: %{page: 0, room: room, room_identity: identity}} = socket, per_page) do
    messages = Rooms.read(room, identity, {nil, 0}, per_page + 1)
    
    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
  end

  defp assign_messages(%{assigns: %{room: room, room_identity: identity, messages: messages}} = socket, per_page) do
    before_message = List.first(messages) 
    messages = Rooms.read(room, identity, {before_message.timestamp, 0}, per_page + 1)
    
    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
  end
end

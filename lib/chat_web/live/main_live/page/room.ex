defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entries: 3]

  alias Phoenix.PubSub

  alias Chat.Identity
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Utils

  def init(%{assigns: %{rooms: rooms, me: me}} = socket, room_hash) do
    room = Rooms.get(room_hash)

    room_identity =
      rooms
      |> Enum.find(&(room_hash == &1 |> Identity.pub_key() |> Utils.hash()))

    messages = room |> Rooms.read(room_identity)

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
    updated_room =
      room
      |> Rooms.add_text(me, text)
      |> tap(&Rooms.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_room |> room_topic(),
      {:new_room_message, updated_room |> Rooms.glimpse()}
    )

    Log.message_room(me, room.pub_key)

    socket
    |> assign(:room, updated_room)
  end

  def send_image(%{assigns: %{me: me, room: room}} = socket) do
    updated_room =
      consume_uploaded_entries(
        socket,
        :room_image,
        fn %{path: path}, entry ->
          data = {File.read!(path), entry.client_type}
          {:ok, Rooms.add_image(room, me, data)}
        end
      )
      |> Enum.at(0)
      |> tap(&Rooms.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_room |> room_topic(),
      {:new_room_message, updated_room |> Rooms.glimpse()}
    )

    Log.message_room(me, room.pub_key)

    socket
    |> assign(:room, updated_room)
  end

  def show_new(%{assigns: %{room_identity: identity}} = socket, glimpse) do
    messages =
      glimpse
      |> Rooms.read(identity)

    socket
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :append)
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
end

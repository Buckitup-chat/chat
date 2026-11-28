defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc """
  Room page: opening and closing a room, storing room keys, and the image gallery hooks.
  Also the stable entry point for `RoomRouter`, `LobbyRouter`, `SyncRoomRouter`, the
  uploader and the proxy pages, which delegates to the room sub-modules:

  - `ChatWeb.MainLive.Page.Room.Messages` — the message list (paging, new, select mode)
  - `ChatWeb.MainLive.Page.Room.MessageActions` — send, edit, delete, re-render a message
  - `ChatWeb.MainLive.Page.Room.Sharing` — downloads and public message links
  - `ChatWeb.MainLive.Page.Room.Requests` — join requests and invites
  - `ChatWeb.MainLive.Page.Room.SyncState` — cargo sync / USB dump availability
  - `ChatWeb.MainLive.Page.Room.Broadcast` — room PubSub topic and broadcasts
  """

  import ChatWeb.LiveHelpers, only: [open_content: 0, send_js: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, send_update: 2, push_patch: 2]

  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.Rooms.{Room, RoomMessageLinks}
  alias Chat.Sync.UsbDriveDumpRoom

  alias ChatWeb.MainLive.Page
  alias ChatWeb.MainLive.Page.Room.{Broadcast, MessageActions, Requests, Sharing, SyncState}
  alias ChatWeb.MainLive.Page.Room.Messages, as: MessageList

  alias Phoenix.PubSub

  defdelegate load_more_messages(socket), to: MessageList
  defdelegate load_new_messages(socket), to: MessageList
  defdelegate show_new(socket, new_message), to: MessageList
  defdelegate toggle_messages_select(socket, params), to: MessageList

  defdelegate send_text(socket, text), to: MessageActions
  defdelegate send_file(socket, entry, metadata), to: MessageActions
  defdelegate edit_message(socket, msg_id), to: MessageActions
  defdelegate update_edited_message(socket, text), to: MessageActions
  defdelegate update_message(socket, msg_id, render_fun), to: MessageActions
  defdelegate cancel_edit(socket), to: MessageActions
  defdelegate delete_messages(socket, params), to: MessageActions
  defdelegate hide_deleted_message(socket, id), to: MessageActions

  defdelegate download_message(socket, msg_id), to: Sharing
  defdelegate download_messages(socket, params), to: Sharing
  defdelegate link_message(socket, msg_id, render_fun), to: Sharing
  defdelegate unlink_messages_modal(socket, component), to: Sharing
  defdelegate unlink_messages(socket, render_fun), to: Sharing
  defdelegate share_message_link_modal(socket, msg_id, component), to: Sharing

  defdelegate approve_request(socket, user_key), to: Requests
  defdelegate open_invite_list(socket, modal), to: Requests
  defdelegate invite_user(socket, user_key), to: Requests

  defdelegate maybe_enable_cargo(socket), to: SyncState
  defdelegate maybe_enable_usb_drive_dump(socket), to: SyncState

  defdelegate broadcast_new_message(message, pub_key, me, time), to: Broadcast

  def init(socket), do: socket |> assign(:room, nil)

  def init(%{assigns: %{room_map: rooms}} = socket, room_key) when is_binary(room_key) do
    with %Room{} = room <- Rooms.get(room_key),
         %Identity{} = room_identity <- Map.get(rooms, room_key) do
      init(socket, {room_identity, room})
    else
      _ ->
        socket
    end
  end

  def init(
        %{assigns: %{me: me, monotonic_offset: time_offset}} = socket,
        {%Identity{} = room_identity, room}
      ) do
    PubSub.subscribe(Chat.PubSub, room.pub_key |> Broadcast.room_topic())

    time = Chat.Time.monotonic_to_unix(time_offset)
    Log.visit_room(me, time, room_identity)

    socket
    |> assign(:page, 0)
    |> assign(:lobby_mode, :rooms)
    |> assign(:input_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:room, room)
    |> assign(:room_identity, room_identity)
    |> assign(:is_room_linked?, RoomMessageLinks.has_room_linked_messages?(room_identity))
    |> assign(:last_load_timestamp, nil)
    |> assign(:has_more_messages, true)
    |> assign(:message_update_mode, :replace)
    |> assign(:usb_drive_dump_room, UsbDriveDumpRoom.get())
    |> MessageList.assign_messages()
    |> MessageList.assign_last_loaded_index()
    |> Requests.assign_requests()
    |> SyncState.maybe_enable_cargo()
    |> SyncState.maybe_enable_usb_drive_dump()
    |> push_event("chat:scroll-down", %{})
  end

  def init_with_linked_message(socket, hash) do
    with {ciphered_identity, _, msg_index, msg_id} <- RoomMessageLinks.get(hash),
         identity <-
           Rooms.decipher_identity(ciphered_identity, hash |> Base.decode16!(case: :lower)),
         room <- identity |> Identity.pub_key() |> Rooms.get() do
      socket
      |> store_new(identity)
      |> init({identity, room})
      |> MessageList.load_messages_to({msg_index, msg_id})
      |> send_js(open_content())
      |> push_patch(to: "/trusted")
    else
      _ ->
        socket
        |> assign(:lobby_mode, :rooms)
        |> init()
        |> push_event("chat:toggle", %{to: "#chatRoomBar", class: "hidden"})
        |> push_event("chat:toggle", %{to: "#navbarLeft", class: "navbar"})
        |> push_event("chat:toggle", %{to: "#navbarLeft", class: "hidden"})
        |> push_event("chat:toggle", %{to: "#navbarTop", class: "navbarTop"})
        |> push_event("chat:toggle", %{to: "#navbarTop", class: "hidden"})
        |> push_event("chat:toggle", %{to: "#navbarBottom", class: "navbarBottom"})
        |> push_event("chat:toggle", %{to: "#navbarBottom", class: "hidden"})
        |> push_event("chat:toggle", %{to: "#contentContainer", class: "hidden"})
    end
  end

  def store_key_copy(%{assigns: %{me: me, room_map: room_map}} = socket, room_identity) do
    if !Map.has_key?(room_map, Identity.pub_key(room_identity)) do
      my_notes = Dialogs.find_or_open(me)

      room_identity
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, my_notes)
      |> RoomInviteIndex.add(my_notes, me, room_identity |> Identity.pub_key())
    end

    socket
  end

  def store_new(socket, new_room_identity) do
    socket
    |> store_key_copy(new_room_identity)
    |> Page.Login.store_new_room(new_room_identity)
    |> Page.Lobby.refresh_room_list()
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket

  def close(%{assigns: %{room: room}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, room.pub_key |> Broadcast.room_topic())
    PubSub.unsubscribe(Chat.PubSub, SyncState.usb_drive_dump_progress_topic())

    socket
    |> assign(:room, nil)
    |> assign(:room_requests, nil)
    |> assign(:room_requests_update_mode, "replace")
    |> assign(:edit_room, nil)
    |> assign(:room_identity, nil)
    |> assign(:messages, nil)
    |> assign(:message_update_mode, nil)
    |> assign(:last_loaded_index, nil)
  end

  def close(socket), do: socket

  def open_image_gallery(socket, msg_id) do
    send_update(Page.ImageGallery, id: "imageGallery", action: :open, incoming_msg_id: msg_id)
    socket
  end

  def image_gallery_preload_next(socket) do
    send_update(Page.ImageGallery, id: "imageGallery", action: :preload_next)

    socket
  end

  def image_gallery_preload_prev(socket) do
    send_update(Page.ImageGallery, id: "imageGallery", action: :preload_prev)

    socket
  end
end

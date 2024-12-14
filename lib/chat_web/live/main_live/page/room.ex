defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"

  use ChatWeb, :component

  import ChatWeb.MainLive.Page.Shared

  import ChatWeb.LiveHelpers,
    only: [
      open_content: 0,
      show_modal: 1,
      open_modal: 3,
      open_modal: 2,
      close_modal: 1,
      send_js: 2
    ]

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [consume_uploaded_entry: 3, push_event: 3, send_update: 2, push_patch: 2]

  require Logger

  alias Chat.Admin.MediaSettings
  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Content.Memo
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.Identity
  alias Chat.Log
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.Rooms.{Registry, Room, RoomMessageLinks, RoomRequest}
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}
  alias Chat.Upload.UploadMetadata
  alias Chat.User
  alias Chat.User.UsersBroker
  alias Chat.Utils
  alias Chat.Utils.StorageId

  alias ChatWeb.MainLive.Page

  alias Phoenix.PubSub

  @per_page 15
  @usb_drive_dump_progress_topic "chat::usb_drive_dump_progress"

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
    PubSub.subscribe(Chat.PubSub, room.pub_key |> room_topic())

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
    |> assign_messages()
    |> assign_last_loaded_index()
    |> assign_requests()
    |> maybe_enable_cargo()
    |> maybe_enable_usb_drive_dump()
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
      |> load_messages_to({msg_index, msg_id})
      |> send_js(open_content())
      |> push_patch(to: "/")
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
    unless Map.has_key?(room_map, Identity.pub_key(room_identity)) do
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

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{input_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def load_new_messages(
        %{
          assigns: %{
            room: room,
            room_identity: identity,
            last_loaded_index: index
          }
        } = socket
      )
      when not is_nil(room) and not is_nil(identity) do
    socket
    |> assign(:message_update_mode, :append)
    |> assign(
      :messages,
      if(index,
        do: Rooms.read_to(room, identity, {nil, 0}, {index + 1, 0}),
        else: Rooms.read(room, identity, {nil, 0}, @per_page + 1)
      )
      |> Chat.Messaging.preload_content()
    )
    |> assign_last_loaded_index()
    |> push_event("chat:scroll-down", %{})
    |> case do
      %{assigns: %{input_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def load_new_messages(socket), do: socket

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
        content
        |> Messages.Text.new(time)
        |> Rooms.add_new_message(me, rooms[room.pub_key])
        |> MemoIndex.add(room, rooms[room.pub_key])
        |> broadcast_new_message(room.pub_key, me, time)
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
      broadcast_new_message(message, pub_key, me, time)
    end)

    socket
  end

  def show_new(
        %{assigns: %{room_identity: %Identity{} = identity}} = socket,
        {index, new_message}
      ) do
    verified_message = Rooms.read_message({index, new_message}, identity)

    if verified_message do
      socket
      |> assign(:page, 0)
      |> assign(:messages, [verified_message])
      |> assign(:message_update_mode, :append)
      |> maybe_update_requests(verified_message)
      |> push_event("chat:scroll-down", %{})
    else
      socket
    end
  end

  def show_new(socket, new_message) do
    identity = socket.assigns[:room_identity] |> inspect()
    message = new_message |> inspect()
    Logger.warning(["Cannot show new message in room. ", "msg: ", message, " room: ", identity])

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
    |> forget_current_messages()
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

    broadcast_message_updated(msg_id, room.pub_key, me, time)

    socket
    |> cancel_edit()
  end

  def update_message(
        %{assigns: %{room_identity: room_identity, my_id: my_id}} = socket,
        {_time, id} = msg_id,
        render_fun
      ) do
    content =
      Rooms.read_message(msg_id, room_identity)
      |> then(&%{msg: &1, my_id: my_id})
      |> render_to_html_string(render_fun)

    socket
    |> forget_current_messages()
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

  def approve_request(%{assigns: %{room_identity: room_identity}} = socket, user_key) do
    room = Rooms.approve_request(room_identity |> Identity.pub_key(), user_key, room_identity)
    Rooms.RoomsBroker.put(room)

    case Rooms.get_request(room, user_key) do
      %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
        PubSub.broadcast!(
          Chat.PubSub,
          "chat::lobby",
          {:room_request_approved, ciphered, user_key, room.pub_key}
        )

      _ ->
        :ok
    end

    socket
    |> assign_requests([user_key])
    |> assign(:room_requests_update_mode, "ignore")
    |> push_event("put-flash", %{key: :info, message: "Request approved!"})
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
      broadcast_deleted_message(msg_id, room.pub_key, me, time)
    end)

    socket
    |> assign(:input_mode, :plain)
  end

  def download_messages(
        %{assigns: %{my_id: my_id, room: room, room_identity: room_identity, timezone: timezone}} =
          socket,
        %{"messages" => messages}
      ) do
    messages_ids =
      messages
      |> Jason.decode!()
      |> Enum.map(fn %{"id" => message_id, "index" => index} ->
        {String.to_integer(index), message_id}
      end)

    key = Broker.store({:room, {messages_ids, room, my_id, room_identity}, timezone})

    push_event(socket, "chat:redirect", %{url: url(~p"/get/zip/#{key}")})
  end

  def hide_deleted_message(socket, id) do
    socket
    |> forget_current_messages()
    |> push_event("chat:toggle", %{to: "#message-block-#{id}", class: "hidden"})
  end

  def open_invite_list(%{assigns: %{db_status: %{writable: :no}}} = socket, _) do
    socket
    |> send_js(show_modal("restrict-write-actions"))
  end

  def open_invite_list(%{assigns: %{my_id: id}} = socket, modal) do
    users = UsersBroker.list() |> Enum.reject(fn user -> user.pub_key == id end)

    if users |> length() > 0 do
      socket |> open_modal(modal, %{users: users})
    else
      socket
    end
  end

  def invite_user(
        %{
          assigns: %{
            room: %{name: room_name, pub_key: room_pub_key},
            room_identity: identity,
            me: me
          }
        } = socket,
        user_key
      ) do
    dialog = Dialogs.find_or_open(me, user_key |> User.by_id())

    identity
    |> Map.put(:name, room_name)
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(me, dialog)
    |> RoomInviteIndex.add(dialog, me, room_pub_key)

    socket
    |> push_event("put-flash", %{key: :info, message: "Invitation Sent!"})
  rescue
    _ -> socket
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket

  def close(%{assigns: %{room: room}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, room.pub_key |> room_topic())
    PubSub.unsubscribe(Chat.PubSub, @usb_drive_dump_progress_topic)

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

  def download_message(
        %{assigns: %{room_identity: room_identity}} = socket,
        msg_id
      ) do
    msg_id
    |> Rooms.read_message(room_identity)
    |> maybe_redirect_to_file(socket)
  end

  def link_message(
        %{assigns: %{room: room, room_identity: room_identity}} = socket,
        {index, id},
        render_fun
      ) do
    :ok = RoomMessageLinks.create(room, room_identity, {index, id})

    socket
    |> assign(:is_room_linked?, true)
    |> push_event("chat:change", %{
      to: "#room-message-#{id} .link-status",
      content: render_to_html_string(%{linked: true, msg_id: id, msg_index: index}, render_fun)
    })
    |> forget_current_messages()
  end

  def unlink_messages_modal(socket, component) do
    socket |> open_modal(component)
  end

  def unlink_messages(%{assigns: %{room_identity: room_identity}} = socket, render_fun) do
    RoomMessageLinks.cancel_room_links(room_identity)
    |> Enum.reduce(socket, fn {_, _, index, id}, socket ->
      content = render_to_html_string(%{linked: false, msg_id: id, msg_index: index}, render_fun)

      socket
      |> push_event("chat:change", %{to: "#room-message-#{id} .link-status", content: content})
    end)
    |> assign(:is_room_linked?, false)
    |> close_modal()
  end

  def share_message_link_modal(%{assigns: %{}} = socket, msg_id, component) do
    message_url =
      [ChatWeb.Endpoint.url(), "room", RoomMessageLinks.link_hash(msg_id)] |> Path.join()

    socket
    |> open_modal(component, %{
      url: message_url,
      encoded_qr_code: Utils.qr_base64_from_url(message_url)
    })
  end

  defp maybe_redirect_to_file(%{type: type, content: json}, socket)
       when type in [:audio, :file, :image, :video] do
    {file_id, secret} = StorageId.from_json(json)
    file_id = Base.encode16(file_id, case: :lower)
    params = %{a: Base.url_encode64(secret)}

    url =
      case type do
        :image ->
          params = Map.put(params, :download, true)
          ~p"/get/image/#{file_id}?#{params}"

        _ ->
          ~p"/get/file/#{file_id}?#{params}"
      end

    push_event(socket, "chat:redirect", %{url: url})
  end

  defp maybe_redirect_to_file(_message, socket), do: socket

  defp maybe_update_requests(socket, message) do
    message.type
    |> case do
      :request -> socket |> assign_requests()
      _ -> socket
    end
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{input_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :plain)
  end

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

  defp room_topic(pub_key) do
    pub_key
    |> Base.encode16(case: :lower)
    |> then(&"room:#{&1}")
  end

  defp assign_messages(socket, per_page \\ @per_page)

  defp assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket

  defp assign_messages(
         %{
           assigns: %{
             room: room,
             room_identity: identity,
             last_load_timestamp: index
           }
         } = socket,
         per_page
       ) do
    messages = Rooms.read(room, identity, {index, 0}, per_page + 1)
    page_messages = Enum.take(messages, -per_page) |> Chat.Messaging.preload_content()

    socket
    |> assign(:messages, page_messages)
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(page_messages))
  end

  defp assign_last_loaded_index(%{assigns: %{messages: messages}} = socket) do
    socket
    |> assign(
      :last_loaded_index,
      List.last(messages)
      |> then(&(get_in(&1, [Access.key!(:index)]) || socket.assigns[:last_loaded_index] || 0))
    )
  end

  defp assign_requests(socket, to_ignore \\ [])

  defp assign_requests(%{assigns: %{room: %{type: :request} = room}} = socket, to_ignore) do
    request_list =
      room.pub_key
      |> Rooms.list_pending_requests()
      |> Enum.reject(fn %RoomRequest{requester_key: pub_key} -> pub_key in to_ignore end)
      |> Enum.map(fn %RoomRequest{requester_key: pub_key} -> User.by_id(pub_key) end)

    socket
    |> assign(:room_requests, request_list)
    |> assign(:room_requests_update_mode, "replace")
  end

  defp assign_requests(socket, _), do: socket |> assign(:room_requests, [])

  defp load_messages_to(%{assigns: %{has_more_messages: false}} = socket, {_, msg_id}) do
    socket
    |> push_event("chat:scroll", %{to: "#message-block-#{msg_id}"})
    |> push_event("chat:toggle", %{to: "#message-block-#{msg_id}", class: "bg-black/10"})
  end

  defp load_messages_to(
         %{
           assigns: %{
             room: room,
             room_identity: identity,
             last_load_timestamp: index,
             messages: messages
           }
         } = socket,
         {msg_index, msg_id}
       ) do
    prev_messages =
      Rooms.read_to(room, identity, {index - 1, 0}, {msg_index, msg_id})
      |> Chat.Messaging.preload_content()

    messages = prev_messages ++ messages

    socket
    |> assign(:messages, messages)
    |> assign(:last_load_timestamp, set_messages_timestamp(messages))
    |> push_event("chat:scroll", %{to: "#message-block-#{msg_id}"})
    |> push_event("chat:toggle", %{to: "#message-block-#{msg_id}", class: "bg-black/10"})
  end

  defp broadcast_message_updated(msg_id, pub_key, me, time) do
    {:updated_message, msg_id}
    |> room_broadcast(pub_key)

    Log.update_room_message(me, time, pub_key)
  end

  def broadcast_new_message(message, pub_key, me, time) do
    {:new_message, message}
    |> room_broadcast(pub_key)

    Log.message_room(me, time, pub_key)
  end

  defp broadcast_deleted_message(msg_id, pub_key, me, time) do
    {:deleted_message, msg_id}
    |> room_broadcast(pub_key)

    Log.delete_room_message(me, time, pub_key)
  end

  defp room_broadcast(message, pub_key) do
    PubSub.broadcast!(
      Chat.PubSub,
      pub_key |> room_topic(),
      {:room, message}
    )
  end

  defp set_messages_timestamp([]), do: nil
  defp set_messages_timestamp([message | _]), do: message.index

  defp forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end

  def maybe_enable_cargo(socket) do
    %MediaSettings{} = media_settings = socket.assigns.media_settings
    room = socket.assigns[:room]

    if media_settings.functionality == :cargo and not is_nil(room) do
      cargo_sync =
        cond do
          match?(%UsbDriveDumpRoom{status: :dumping}, socket.assigns[:usb_drive_dump_room]) ->
            :disabled

          match?(
            %CargoRoom{pub_key: pub_key, status: status}
            when pub_key == room.pub_key or status == :syncing,
            socket.assigns[:cargo_room]
          ) ->
            :disabled

          !has_unique_name(room) ->
            :duplicate_name

          true ->
            :enabled
        end

      assign(socket, :cargo_sync, cargo_sync)
    else
      assign(socket, :cargo_sync, nil)
    end
  end

  defp has_unique_name(%Room{} = room) do
    Registry.all()
    |> Enum.any?(fn {_room_pub_key, %Room{} = other_room} ->
      other_room.name == room.name and other_room.pub_key != room.pub_key
    end)
    |> Kernel.not()
  end

  def maybe_enable_usb_drive_dump(%{assigns: %{room: room}} = socket) when not is_nil(room) do
    PubSub.unsubscribe(Chat.PubSub, @usb_drive_dump_progress_topic)

    usb_drive_dump =
      cond do
        match?(%CargoRoom{status: :syncing}, socket.assigns[:cargo_room]) ->
          :disabled

        match?(
          %UsbDriveDumpRoom{pub_key: pub_key, status: status}
          when pub_key == room.pub_key or status == :dumping,
          socket.assigns[:usb_drive_dump_room]
        ) ->
          PubSub.subscribe(Chat.PubSub, @usb_drive_dump_progress_topic)
          :disabled

        true ->
          :enabled
      end

    assign(socket, :usb_drive_dump, usb_drive_dump)
  end

  def maybe_enable_usb_drive_dump(socket), do: socket
end

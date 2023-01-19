defmodule ChatWeb.MainLive.Page.Room do
  @moduledoc "Room page"

  use ChatWeb, :component

  import ChatWeb.MainLive.Page.Shared
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3, put_flash: 3]

  require Logger

  alias Chat.Broker
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Memo
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.Upload.UploadMetadata
  alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId

  alias ChatWeb.Router.Helpers, as: Routes

  alias Phoenix.PubSub

  @per_page 15

  def init(socket), do: socket |> assign(:room, nil)

  def init(%{assigns: %{rooms: rooms, me: me, monotonic_offset: time_offset}} = socket, room_hash) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    room = Rooms.get(room_hash)

    room_identity =
      rooms
      |> Enum.find(&(room_hash == &1 |> Identity.pub_key() |> Utils.hash()))

    PubSub.subscribe(Chat.PubSub, room.pub_key |> room_topic())
    Log.visit_room(me, time, room_identity)

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
    |> assign_requests()
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{room_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

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
        |> Rooms.add_new_message(me, room.pub_key)
        |> MemoIndex.add(room, rooms[room.pub_key |> Utils.hash()])
        |> broadcast_new_message(room.pub_key, me, time)
    end

    socket
  end

  def send_file(
        %{assigns: %{me: me, monotonic_offset: time_offset}} = socket,
        entry,
        %UploadMetadata{credentials: {chunk_key, chunk_secret}, destination: %{pub_key: pub_key}} =
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
            chunk_secret,
            time
          )
          |> Rooms.add_new_message(me, pub_key)
          |> then(&{:ok, &1})
        end
      )

    FileIndex.add_file(chunk_key, pub_key)

    Rooms.on_saved(message, pub_key, fn ->
      broadcast_new_message(message, pub_key, me, time)
    end)

    socket
  end

  def show_new(
        %{assigns: %{room_identity: identity}} = socket,
        {index, %{author_hash: hash, encrypted: {data, sign}} = new_message}
      ) do
    if Utils.is_signed_by?(sign, data, User.by_id(hash)) do
      socket
      |> assign(:page, 0)
      |> assign(:messages, [{index, new_message} |> Rooms.read_message(identity)])
      |> assign(:message_update_mode, :append)
      |> push_event("chat:scroll-down", %{})
    else
      socket
    end
  end

  def show_new(socket, new_message) do
    identity = socket.assigns[:room_identity] |> inspect()
    message = new_message |> inspect()
    Logger.warn("Cannot show new message in room. msg: #{message} room: #{identity}")

    socket
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
      Rooms.read_message(msg_id, room_identity, &User.id_map_builder/1)
      |> then(&%{msg: &1, my_id: my_id})
      |> render_to_html_string(render_fun)

    socket
    |> forget_current_messages()
    |> push_event("chat:change", %{to: "#room-message-#{id} .x-content", content: content})
  end

  def update_message(socket, msg_id, _) do
    identity = socket.assigns[:room_identity] |> inspect()

    Logger.warn(
      "Cannot show upated message in room. msg_id: #{inspect(msg_id)} room: #{identity}"
    )

    socket
  end

  def cancel_edit(socket) do
    socket
    |> assign(:room_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_message(
        %{
          assigns: %{
            me: me,
            room_identity: room_identity,
            room: room,
            monotonic_offset: time_offset
          }
        } = socket,
        {index, msg_id}
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    Rooms.delete_message({index, msg_id}, room_identity, me)
    broadcast_deleted_message(msg_id, room, me, time)

    socket
  end

  def approve_request(%{assigns: %{room_identity: room_identity}} = socket, user_hash) do
    Rooms.approve_request(room_identity |> Utils.hash(), user_hash, room_identity)

    socket
    |> put_flash(:info, "Request approved!")
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
      broadcast_deleted_message(msg_id, room, me, time)
    end)

    socket
    |> assign(:room_mode, :plain)
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

  def invite_user(
        %{assigns: %{room: %{name: room_name}, room_identity: identity, me: me}} = socket,
        user_hash
      ) do
    dialog = Dialogs.find_or_open(me, user_hash |> User.by_id())

    identity
    |> Map.put(:name, room_name)
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(me, dialog)
    |> RoomInviteIndex.add(dialog, me)

    socket
    |> put_flash(:info, "Invitation Sent!")
  rescue
    _ -> socket
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket

  def close(%{assigns: %{room: room}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, room.pub_key |> room_topic())

    socket
    |> assign(:room, nil)
    |> assign(:room_requests, nil)
    |> assign(:edit_room, nil)
    |> assign(:room_identity, nil)
    |> assign(:messages, nil)
    |> assign(:message_update_mode, nil)
  end

  def close(socket), do: socket

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

      %{type: :video, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        socket
        |> push_event("chat:redirect", %{
          url: Routes.file_url(socket, :file, id, a: secret |> Base.url_encode64())
        })

      _ ->
        socket
    end
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:room_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{room_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:room_mode, :plain)
  end

  def open_image_gallery(
        %{assigns: %{room_identity: room_identity}} = socket,
        {m_index, m_id} = msg_id
      ) do
    send(self(), {:room, {:preload_image_gallery, :next}})
    send(self(), {:room, {:preload_image_gallery, :prev}})

    Rooms.read_message(msg_id, room_identity, &User.id_map_builder/1)
    |> case do
      %{type: :image, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        socket
        |> assign(:image_gallery, %{
          mode: "room",
          current: %{
            url: Routes.file_url(socket, :image, id, a: secret |> Base.url_encode64()),
            id: m_id,
            index: m_index
          },
          next: %{url: nil, id: nil, index: nil},
          prev: %{url: nil, id: nil, index: nil}
        })

      _ ->
        socket
    end
  end

  def image_gallery_preload_next(
        %{assigns: %{room_identity: identity, image_gallery: gallery}} = socket
      ) do
    msg_id = {gallery.current.index, gallery.current.id}

    msg_id
    |> Rooms.read_next_message(identity, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        socket
        |> assign(
          :image_gallery,
          gallery
          |> put_in([:next], %{
            url: Routes.file_url(socket, :image, file_id, a: secret |> Base.url_encode64()),
            id: id,
            index: index
          })
        )

      _ ->
        socket
    end
  end

  def image_gallery_preload_prev(
        %{assigns: %{room_identity: identity, image_gallery: gallery}} = socket
      ) do
    msg_id = {gallery.current.index, gallery.current.id}

    msg_id
    |> Rooms.read_prev_message(identity, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        socket
        |> assign(
          :image_gallery,
          gallery
          |> put_in([:prev], %{
            url: Routes.file_url(socket, :image, file_id, a: secret |> Base.url_encode64()),
            id: id,
            index: index
          })
        )

      _ ->
        socket
    end
  end

  def image_gallery_next(
        %{assigns: %{image_gallery: %{mode: mode, current: current, next: next}}} = socket
      ) do
    send(self(), {:room, {:preload_image_gallery, :next}})

    socket
    |> assign(:image_gallery, %{
      mode: mode,
      current: next,
      prev: current,
      next: %{url: nil, id: nil, index: nil}
    })
  end

  def image_gallery_prev(
        %{assigns: %{image_gallery: %{mode: mode, current: current, prev: prev}}} = socket
      ) do
    send(self(), {:room, {:preload_image_gallery, :prev}})

    socket
    |> assign(:image_gallery, %{
      mode: mode,
      current: prev,
      next: current,
      prev: %{url: nil, id: nil, index: nil}
    })
  end

  def close_image_gallery(socket) do
    socket
    |> assign(:image_gallery, nil)
  end

  defp room_topic(pub_key) do
    pub_key
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
             last_load_timestamp: index
           }
         } = socket,
         per_page
       ) do
    messages = Rooms.read(room, identity, &User.id_map_builder/1, {index, 0}, per_page + 1)
    page_messages = Enum.take(messages, -per_page)

    socket
    |> assign(:messages, page_messages)
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(page_messages))
  end

  defp assign_requests(%{assigns: %{room: %{type: :request} = room}} = socket) do
    request_list =
      room.pub_key
      |> Utils.hash()
      |> Rooms.list_pending_requests()
      |> Enum.map(fn {hash, _} -> User.by_id(hash) end)

    socket
    |> assign(:room_requests, request_list)
  end

  defp assign_requests(socket), do: socket

  defp broadcast_message_updated(msg_id, pub_key, me, time) do
    {:updated_message, msg_id}
    |> room_broadcast(pub_key)

    Log.update_room_message(me, time, pub_key)
  end

  defp broadcast_new_message(message, pub_key, me, time) do
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
end

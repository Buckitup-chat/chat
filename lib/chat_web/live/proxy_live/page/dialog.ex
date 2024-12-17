defmodule ChatWeb.ProxyLive.Page.Dialog do
  @moduledoc "Dialog page"
  use ChatWeb, :component

  require Logger

  import ChatWeb.MainLive.Page.Shared
  import ChatWeb.LiveHelpers.SocketPrivate
  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [consume_uploaded_entry: 3, push_event: 3, send_update: 2, push_patch: 2]

  alias Chat.AdminRoom
  alias Chat.Broker
  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.Content.Memo
  alias Chat.Content.RoomInvites
  alias Chat.Dialogs
  alias Chat.Dialogs.DialogMessaging
  alias Chat.FileIndex
  alias Chat.Identity
  alias Chat.Log
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Sync.DbBrokers
  alias Chat.Upload.UploadMetadata
  # alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId

  alias ChatWeb.MainLive.Page

  alias Phoenix.PubSub

  @per_page 15

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:dialog, nil)
    |> assign(:peer, nil)
  end

  def init(socket, user_id) do
    actor = socket |> get_private(:actor)
    user_cache = socket |> get_private(:users_cache)
    peer_pub_key = user_id |> Base.decode16!(case: :lower)
    peer = Enum.find(user_cache, &(&1.pub_key == peer_pub_key))

    # time = Chat.Time.monotonic_to_unix(socket.assigns.monotonic_offset)
    # peer = User.by_id(user_id |> Base.decode16!(case: :lower))
    dialog = Dialogs.find_or_open(actor.me, peer)

    # PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())
    # Log.open_direct(me, time, peer)

    socket
    |> assign(:page, 0)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:input_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:has_more_messages, true)
    |> assign(:last_load_timestamp, nil)
    |> assign(:message_update_mode, :replace)
    |> assign_messages()
    |> send_js(open_content())

    # may be to support chat redirects
    # |> push_patch(to: "/")
  rescue
    _ ->
      socket |> push_patch(to: "/")
  end

  def handle_event(msg, params, socket) do
    case msg do
      "dialog/switch" -> socket |> switch_dialog(params)
      "chat:load-more" -> socket |> load_more_messages()
      "dialog/message/open-image-gallery" -> socket |> open_image_gallery(params)
      "dialog/text-message" -> socket |> send_text_message(params)
      _ -> socket |> tap(fn _ -> dbg([msg, params]) end)
    end
  end

  def handle_info(msg, socket) do
    case msg do
      {:loaded_messages, messages, amount, dialog} ->
        socket |> add_loaded_messages(messages, amount, dialog)

      {:new_dialog_message, {dialog_key, indexed_message}} ->
        current_dialog = socket.assigns.dialog

        if current_dialog && Chat.Dialogs.key(current_dialog) == dialog_key,
          do: socket |> show_new(indexed_message),
          else: socket

      {_anything, _} ->
        socket
    end
  end

  defp switch_dialog(socket, %{"user-id" => user_id}) do
    socket
    |> close()
    |> init(user_id)
  end

  defp add_loaded_messages(socket, messages, amount, dialog) do
    if dialog == socket.assigns.dialog do
      new_messages = Enum.take(messages, -amount)

      last_index =
        case new_messages do
          [first | _] when is_map(first) -> Map.get(first, :index)
          _ -> nil
        end

      socket
      |> assign(:messages, new_messages)
      |> assign(:has_more_messages, Enum.count(messages) > amount)
      |> assign(:last_load_timestamp, last_index)
    else
      socket
    end
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

  def open_image_gallery(socket, msg_id) do
    server = socket |> get_private(:server)
    %{dialog: dialog, me: me} = socket.assigns

    send_update(Page.ImageGallery,
      id: "imageGallery",
      action: :open,
      incoming_msg_id: msg_id,
      type: :proxy_dialog,
      server: server,
      dialog: dialog,
      me: me
    )

    socket
  end

  def send_text_message(socket, params) do
    server = socket |> get_private(:server)
    %{dialog: dialog, me: me} = socket.assigns
    %{"dialog" => %{"text" => text}} = params
    trimmed_text = String.trim(text)

    if trimmed_text != "" do
      time = DateTime.utc_now() |> DateTime.to_unix(:second)

      Task.start(fn ->
        %Messages.Text{text: text, timestamp: time}
        |> Chat.SignedParcel.wrap_dialog_message(dialog, me)
        |> Proxy.save_parcel(server, me)
      end)
    end

    socket
  end

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    server = socket |> get_private(:server)

    messages =
      [DialogMessaging.read(new_message, me, dialog)]
      |> Enum.reject(&is_nil/1)
      |> Chat.Messaging.preload_content(&Proxy.get_data_by_keys(server, &1))

    socket
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
    |> push_event("chat:scroll-down", %{})
  end

  #
  # Copy paste from main_live
  #

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
        |> broadcast_new_message(dialog, me, time)
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
      broadcast_new_message(message, dialog, me, time)
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
    |> forget_current_messages()
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
      broadcast_message_updated(msg_id, dialog, me, time)
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
    |> forget_current_messages()
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
      broadcast_message_deleted(msg_id, dialog, me, time)
    end)

    socket
    |> assign(:input_mode, :plain)
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
    |> maybe_redirect_to_file(socket)
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

  def download_messages(
        %{assigns: %{dialog: dialog, me: me, peer: peer, timezone: timezone}} = socket,
        %{"messages" => messages}
      ) do
    messages_ids =
      messages
      |> Jason.decode!()
      |> Enum.map(fn %{"id" => message_id, "index" => index} ->
        {String.to_integer(index), message_id}
      end)

    key = Broker.store({:dialog, {dialog, messages_ids, me, peer}, timezone})

    push_event(socket, "chat:redirect", %{url: url(~p"/get/zip/#{key}")})
  end

  def accept_room_invite(
        %{assigns: %{room_map: room_map}} = socket,
        %{type: :room_invite, content: content} = msg,
        render_fun
      ) do
    new_room_identity =
      content
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    if Map.has_key?(room_map, Identity.pub_key(new_room_identity)) do
      socket
    else
      socket
      |> Page.Room.store_new(new_room_identity)
      |> update_invite_navigation(msg, new_room_identity, render_fun)
    end
  rescue
    _ -> socket
  end

  def accept_room_invite(%{assigns: %{me: me, dialog: dialog}} = socket, message_id, render_fun) do
    socket
    |> accept_room_invite(Dialogs.read_message(dialog, message_id, me), render_fun)
  end

  def accept_room_invite_and_open_room(
        %{assigns: %{me: me, dialog: dialog, room_map: room_map}} = socket,
        message_id
      ) do
    new_room_identity =
      Dialogs.read_message(dialog, message_id, me)
      |> then(fn %{type: :room_invite, content: json} -> json end)
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    socket =
      if Map.has_key?(room_map, Identity.pub_key(new_room_identity)) do
        socket
      else
        socket
        |> Page.Room.store_new(new_room_identity)
      end
      |> close()

    if new_room_identity.public_key == AdminRoom.pub_key() do
      socket
      |> Page.Lobby.switch_lobby_mode("admin")
      |> tap(fn _ -> DbBrokers.broadcast_refresh() end)
    else
      socket
      |> Page.Room.init(
        {new_room_identity, new_room_identity |> Identity.pub_key() |> Rooms.get()}
      )
    end
  rescue
    _ -> socket
  end

  def accept_all_room_invites(%{assigns: %{dialog: dialog, me: me}} = socket) do
    Dialogs.list_room_invites(dialog, me)
    |> Enum.reverse()
    |> Enum.each(fn invite ->
      send(self(), {:dialog, {:accept_room_invite, invite}})
    end)

    socket
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

  def image_gallery_preload_next(socket) do
    send_update(Page.ImageGallery, id: "imageGallery", action: :preload_next)

    socket
  end

  def show_link_modal(%{assigns: %{}} = socket, hash, component) do
    chat_url = [ChatWeb.Endpoint.url(), "chat", hash] |> Path.join()

    socket
    |> open_modal(component, %{url: chat_url, encoded_qr_code: Utils.qr_base64_from_url(chat_url)})
  end

  def image_gallery_preload_prev(socket) do
    send_update(Page.ImageGallery, id: "imageGallery", action: :preload_prev)

    socket
  end

  def close(%{assigns: %{dialog: nil}} = socket), do: socket

  def close(%{assigns: %{dialog: dialog}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
    |> assign(:image_gallery, nil)
  end

  defp dialog_topic(%Dialogs.Dialog{} = dialog) do
    dialog
    |> Dialogs.key()
    |> then(&"dialog:#{&1}")
  end

  defp assign_messages(socket, per_page \\ @per_page)

  defp assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket

  defp assign_messages(
         %{assigns: %{dialog: dialog, last_load_timestamp: max_index}} = socket,
         per_page
       ) do
    server = socket |> get_private(:server)
    actor = socket |> get_private(:actor)
    pid = self()

    Task.start(fn ->
      peer = Dialogs.peer(dialog, actor.me)
      Proxy.find_or_create_dialog(server, actor.me, peer)

      messages =
        Proxy.get_dialog_messages(server, dialog, max_index, per_page + 1)
        |> Enum.map(fn {{:dialog_message, _, index, _}, msg} ->
          {index, msg} |> DialogMessaging.read(actor.me, dialog)
        end)
        |> Enum.filter(& &1)
        |> Enum.reverse()
        |> Chat.Messaging.preload_content(&Proxy.get_data_by_keys(server, &1))
        |> Enum.map(fn
          %{type: type, content: json} = msg when type in [:image, :audio, :file, :video] ->
            {id, secret} = json |> StorageId.from_json()

            msg
            |> Map.put(:file_url, ChatWeb.Utils.get_proxied_file_url(server, id, secret))

          simple_message ->
            simple_message
        end)

      send(pid, {:dialog, {:loaded_messages, messages, per_page, dialog}})
    end)

    socket
    |> assign(:messages, [])
  end

  defp broadcast_new_message(nil, _, _, _), do: nil

  defp broadcast_new_message(message, dialog, me, time) do
    {:new_dialog_message, message}
    |> dialog_broadcast(dialog)

    Log.message_direct(me, time, Dialogs.peer(dialog, me))
  end

  defp broadcast_message_updated(message_id, dialog, me, time) do
    {:updated_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.update_message_direct(me, time, Dialogs.peer(dialog, me))
  end

  defp broadcast_message_deleted(message_id, dialog, me, time) do
    {:deleted_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.delete_message_direct(me, time, Dialogs.peer(dialog, me))
  end

  defp dialog_broadcast(message, dialog) do
    PubSub.broadcast!(
      Chat.PubSub,
      dialog |> dialog_topic(),
      {:dialog, message}
    )
  end

  # defp set_messages_timestamp([]), do: nil
  # defp set_messages_timestamp([message | _]), do: message.index

  defp forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end

  defp update_invite_navigation(
         %{assigns: %{room_map: room_map}} = socket,
         msg,
         room_identity,
         render_fun
       ) do
    room_hash = room_identity |> Card.from_identity() |> Enigma.short_hash()
    room_key = room_identity |> Identity.pub_key()

    socket
    |> push_event("chat:bulk-change", %{
      to: ".x-invite-navigation[data-room='#{room_hash}']",
      content:
        render_to_html_string(
          %{msg: msg, room_key: room_key, room_keys: Map.keys(room_map)},
          render_fun
        )
    })
  end
end

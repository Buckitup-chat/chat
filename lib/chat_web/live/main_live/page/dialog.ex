defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc "Dialog page"
  import ChatWeb.MainLive.Page.Shared
  import Phoenix.LiveView, only: [assign: 3, consume_uploaded_entry: 3, push_event: 3]

  use Phoenix.Component

  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Log
  alias Chat.Memo
  alias Chat.Messages
  alias Chat.RoomInvites
  alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId

  alias ChatWeb.MainLive.Page
  alias ChatWeb.Router.Helpers, as: Routes

  alias Phoenix.PubSub

  @per_page 15

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:dialog, nil)
    |> assign(:peer, nil)
  end

  def init(%{assigns: %{me: me, client_timestamp: time}} = socket, user_id) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)

    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())
    Log.open_direct(me, time, peer)

    socket
    |> assign(:page, 0)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:dialog_mode, :plain)
    |> assign(:has_more_messages, true)
    |> assign(:last_load_timestamp, nil)
    |> assign(:message_update_mode, :replace)
    |> assign_messages()
  end

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{dialog_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def send_text(
        %{assigns: %{dialog: dialog, me: me, client_timestamp: time}} = socket,
        text
      ) do
    text
    |> String.trim()
    |> case do
      "" ->
        nil

      text ->
        %Messages.Text{text: text, timestamp: time}
        |> Dialogs.add_new_message(me, dialog)
        |> broadcast_new_message(dialog, me, time)
    end

    socket
  end

  def send_file(
        %{assigns: %{dialog: dialog, me: me, client_timestamp: time}} = socket,
        entry,
        {chunk_key, chunk_secret}
      ) do
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
        |> Dialogs.add_new_message(me, dialog)
        |> then(&{:ok, &1})
      end
    )
    |> broadcast_new_message(dialog, me, time)

    socket
  end

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    socket
    |> assign(:messages, [Dialogs.read_message(dialog, new_message, me)])
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
    |> push_event("chat:scroll-down", %{})
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
    |> assign(:dialog_mode, :edit)
    |> assign(:edit_content, content)
    |> assign(:edit_message_id, msg_id)
    |> forget_current_messages()
    |> push_event("chat:focus", %{to: "#dialog-edit-input"})
  end

  def update_edited_message(
        %{assigns: %{dialog: dialog, me: me, edit_message_id: msg_id, client_timestamp: time}} =
          socket,
        text
      ) do
    text
    |> Messages.Text.new(time)
    |> Dialogs.update_message(msg_id, me, dialog)

    broadcast_message_updated(msg_id, dialog, me, time)

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
    |> assign(:dialog_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:edit_message_id, nil)
  end

  def delete_message(
        %{assigns: %{me: me, dialog: dialog, client_timestamp: time}} = socket,
        {time, msg_id}
      ) do
    Dialogs.delete(dialog, me, {time, msg_id})
    broadcast_message_deleted(msg_id, dialog, me, time)

    socket
  end

  def delete_messages(%{assigns: %{me: me, dialog: dialog, client_timestamp: time}} = socket, %{
        "messages" => messages
      }) do
    messages
    |> Jason.decode!()
    |> Enum.each(fn %{"id" => msg_id, "index" => index} ->
      Dialogs.delete(dialog, me, {String.to_integer(index), msg_id})
      broadcast_message_deleted(msg_id, dialog, me, time)
    end)

    socket
    |> assign(:dialog_mode, :plain)
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

  def accept_room_invite(%{assigns: %{me: me, dialog: dialog, rooms: rooms}} = socket, message_id) do
    new_room_identitiy =
      Dialogs.read_message(dialog, message_id, me)
      |> then(fn %{type: :room_invite, content: json} -> json end)
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    if rooms |> Enum.any?(&(&1.priv_key == new_room_identitiy.priv_key)) do
      socket
    else
      socket
      |> Page.Login.store_new_room(new_room_identitiy)
      |> Page.Lobby.refresh_room_list()
    end
  rescue
    _ -> socket
  end

  def accept_room_invite_and_open_room(
        %{assigns: %{me: me, dialog: dialog, rooms: rooms}} = socket,
        message_id
      ) do
    new_room_identitiy =
      Dialogs.read_message(dialog, message_id, me)
      |> then(fn %{type: :room_invite, content: json} -> json end)
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    room_hash = new_room_identitiy |> Utils.hash()

    if rooms |> Enum.any?(&(&1.priv_key == new_room_identitiy.priv_key)) do
      socket
    else
      socket
      |> Page.Login.store_new_room(new_room_identitiy)
      |> Page.Lobby.refresh_room_list()
    end
    |> close()
    |> Page.Room.init(room_hash)
  rescue
    _ -> socket
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:dialog_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{dialog_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:dialog_mode, :plain)
  end

  def open_image_gallery(
        %{assigns: %{me: me, dialog: dialog}} = socket,
        {m_index, m_id} = msg_id
      ) do
    send(self(), {:dialog, {:preload_image_gallery, :next}})
    send(self(), {:dialog, {:preload_image_gallery, :prev}})

    dialog
    |> Dialogs.read_message(msg_id, me)
    |> case do
      %{type: :image, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        socket
        |> assign(:image_gallery, %{
          mode: "dialog",
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
        %{assigns: %{dialog: dialog, me: me, image_gallery: gallery}} = socket
      ) do
    msg_id = {gallery.current.index, gallery.current.id}

    dialog
    |> Dialogs.read_next_message(msg_id, me, fn
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
        %{assigns: %{dialog: dialog, me: me, image_gallery: gallery}} = socket
      ) do
    msg_id = {gallery.current.index, gallery.current.id}

    dialog
    |> Dialogs.read_prev_message(msg_id, me, fn
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
    send(self(), {:dialog, {:preload_image_gallery, :next}})

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
    send(self(), {:dialog, {:preload_image_gallery, :prev}})

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
         %{assigns: %{dialog: dialog, me: me, last_load_timestamp: timestamp}} = socket,
         per_page
       ) do
    messages = Dialogs.read(dialog, me, {timestamp, 0}, per_page + 1)

    socket
    |> assign(:messages, Enum.take(messages, -per_page))
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(messages))
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

  defp set_messages_timestamp([]), do: nil
  defp set_messages_timestamp([message | _]), do: message.index

  defp forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end
end

defmodule ChatWeb.MainLive.Page.Dialog do
  @moduledoc """
  Dialog page: opening and closing a dialog, and the image gallery hooks. Also the
  stable entry point for `ChatWeb.MainLive.Page.DialogRouter` and the other pages,
  which delegates to the dialog sub-modules:

  - `ChatWeb.MainLive.Page.Dialog.Messages` — the message list (paging, new, select mode)
  - `ChatWeb.MainLive.Page.Dialog.MessageActions` — send, edit, delete, re-render a message
  - `ChatWeb.MainLive.Page.Dialog.Sharing` — downloads and the chat link modal
  - `ChatWeb.MainLive.Page.Dialog.Invites` — room invites received in the dialog
  - `ChatWeb.MainLive.Page.Dialog.Broadcast` — dialog PubSub topic and broadcasts
  """

  import ChatWeb.LiveHelpers, only: [open_content: 0, send_js: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2, push_patch: 2]

  alias Chat.Dialogs
  alias Chat.Log
  alias Chat.User
  alias ChatWeb.MainLive.Page
  alias ChatWeb.MainLive.Page.Dialog.Broadcast
  alias ChatWeb.MainLive.Page.Dialog.Invites
  alias ChatWeb.MainLive.Page.Dialog.MessageActions
  alias ChatWeb.MainLive.Page.Dialog.Messages, as: MessageList
  alias ChatWeb.MainLive.Page.Dialog.Sharing
  alias Phoenix.PubSub

  defdelegate load_more_messages(socket), to: MessageList
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
  defdelegate show_link_modal(socket, hash, component), to: Sharing

  defdelegate accept_room_invite(socket, msg_or_id, render_fun), to: Invites
  defdelegate accept_room_invite_and_open_room(socket, message_id), to: Invites
  defdelegate accept_all_room_invites(socket), to: Invites

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:dialog, nil)
    |> assign(:peer, nil)
  end

  def init(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, user_id) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    peer = User.by_id(user_id |> Base.decode16!(case: :lower))
    dialog = Dialogs.find_or_open(me, peer)

    PubSub.subscribe(Chat.PubSub, dialog |> Broadcast.dialog_topic())
    Log.open_direct(me, time, peer)

    socket
    |> assign(:page, 0)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:input_mode, :plain)
    |> assign(:edit_content, nil)
    |> assign(:has_more_messages, true)
    |> assign(:last_load_timestamp, nil)
    |> assign(:message_update_mode, :replace)
    |> MessageList.assign_messages()
    |> send_js(open_content())
    |> push_patch(to: "/trusted")
  rescue
    _ ->
      socket |> push_patch(to: "/trusted")
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

  def close(%{assigns: %{dialog: nil}} = socket), do: socket

  def close(%{assigns: %{dialog: dialog}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, dialog |> Broadcast.dialog_topic())

    socket
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
    |> assign(:image_gallery, nil)
  end
end

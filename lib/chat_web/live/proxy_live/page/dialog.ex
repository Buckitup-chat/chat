defmodule ChatWeb.ProxyLive.Page.Dialog do
  @moduledoc """
  Proxy dialog page: opening, switching and closing a dialog on the proxied server,
  event/info dispatch and the image gallery hooks. Also the stable entry point for
  `ChatWeb.ProxyLive.Index`, `ChatWeb.ProxyLive.Init` and the proxy lobby, which
  delegates to the dialog sub-modules:

  - `ChatWeb.ProxyLive.Page.Dialog.Messages` — the message list (paging, new, select mode)
  - `ChatWeb.ProxyLive.Page.Dialog.MessageActions` — send, edit, delete, re-render a message
  - `ChatWeb.ProxyLive.Page.Dialog.Sharing` — downloads and the chat link modal
  - `ChatWeb.ProxyLive.Page.Dialog.Invites` — room invites received in the dialog
  - `ChatWeb.ProxyLive.Page.Dialog.Broadcast` — dialog PubSub topic and broadcasts
  """

  require Logger

  import ChatWeb.LiveHelpers, only: [open_content: 0, send_js: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2, push_patch: 2]
  import Tools.SocketPrivate

  alias Chat.Dialogs
  alias ChatWeb.MainLive.Page
  alias ChatWeb.ProxyLive.Page.Dialog.Broadcast
  alias ChatWeb.ProxyLive.Page.Dialog.Invites
  alias ChatWeb.ProxyLive.Page.Dialog.MessageActions
  alias ChatWeb.ProxyLive.Page.Dialog.Messages, as: MessageList
  alias ChatWeb.ProxyLive.Page.Dialog.Sharing
  alias ChatWeb.State.ActorState
  alias Proxy.SocketClient

  defdelegate load_more_messages(socket), to: MessageList
  defdelegate show_new(socket, new_message), to: MessageList
  defdelegate toggle_messages_select(socket, params), to: MessageList

  defdelegate send_text_message(socket, params), to: MessageActions
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

  def init(socket, user_id) do
    user_cache = socket |> get_private(:users_cache)
    peer_pub_key = user_id |> Base.decode16!(case: :lower)
    peer = Enum.find(user_cache, &(&1.pub_key == peer_pub_key))

    # local  but used for key only = kinda ok
    dialog = Dialogs.find_or_open(ActorState.my_identity(socket), peer)

    socket
    |> SocketClient.join(dialog |> Broadcast.dialog_topic())

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
  rescue
    _ ->
      socket |> push_patch(to: "/trusted")
  end

  def handle_event(msg, params, socket) do
    case msg do
      "dialog/switch" ->
        socket |> switch_dialog(params)

      "chat:load-more" ->
        socket |> MessageList.load_more_messages()

      "dialog/message/open-image-gallery" ->
        socket |> open_image_gallery(params)

      "dialog/text-message" ->
        socket |> MessageActions.send_text_message(params)

      _ ->
        socket
        |> tap(fn _ -> Logger.warning(["unhandled dialog event ", inspect({msg, params})]) end)
    end
  end

  def handle_info(msg, socket) do
    case msg do
      {:loaded_messages, messages, amount, dialog} ->
        socket |> MessageList.add_loaded_messages(messages, amount, dialog)

      {:new_dialog_message, {dialog_key, indexed_message}} ->
        current_dialog = socket.assigns.dialog

        if current_dialog && Chat.Dialogs.key(current_dialog) == dialog_key,
          do: socket |> MessageList.show_new(indexed_message),
          else: socket

      anything ->
        Logger.warning(["unhandled dialog info ", inspect(anything)])
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
    socket
    |> SocketClient.leave(dialog |> Broadcast.dialog_topic())
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
    |> assign(:image_gallery, nil)
  end

  defp switch_dialog(socket, %{"user-id" => user_id}) do
    socket
    |> close()
    |> init(user_id)
  end
end

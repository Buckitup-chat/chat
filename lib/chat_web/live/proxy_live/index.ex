defmodule ChatWeb.ProxyLive.Index do
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Rooms.Room

  alias ChatWeb.ProxyLive.Init

  alias ChatWeb.Hooks.LiveModalHook
  alias ChatWeb.Hooks.UploaderHook
  alias ChatWeb.MainLive.Layout
  alias ChatWeb.MainLive.Page
  alias ChatWeb.MainLive.Page.RoomForm

  alias ChatWeb.ProxyLive.Page.Dialog, as: ProxyDialog
  alias ChatWeb.ProxyLive.Page.Lobby, as: ProxyLobby
  alias ChatWeb.ProxyLive.Page.Room, as: ProxyRoom

  # alias ChatWeb.ProxyLive.Components.Dialog
  # alias ChatWeb.ProxyLive.Components.UserList

  on_mount LiveModalHook
  on_mount UploaderHook

  embed_templates "*"
  embed_templates "../main_live/chats*"
  embed_templates "../main_live/rooms*"

  def mount(params, session, socket) do
    [
      &Init.check_connected(&1),
      &Init.extract_actor(&1),
      &Init.extract_address(&1, params),
      &Init.mimic_main_page_mount(&1, session)
    ]
    |> Init.run_steps(socket)
    |> ok()
  end

  def handle_event(msg, params, socket) do
    case msg do
      "lobby/" <> _ -> ProxyLobby.handle_event(msg, params, socket)
      "switch-lobby-mode" -> ProxyLobby.switch_lobby_mode(socket, params)
      "dialog/" <> _ -> ProxyDialog.handle_event(msg, params, socket)
      "room/send-request" <> _ -> ProxyLobby.handle_event(msg, params, socket)
      "room/sync-stored" -> ProxyLobby.handle_event(msg, params, socket)
      "room/" <> _ -> ProxyRoom.handle_event(msg, params, socket)
      "chat:load-more" -> handle_general_event(msg, params, socket)
      "chat:" <> _ -> ProxyDialog.handle_event(msg, params, socket)
      "local-time" -> socket
    end
    |> noreply()
  end

  def handle_general_event(msg, params, socket) do
    case {msg, socket.assigns} do
      {"chat:load-more", %{dialog: _}} -> ProxyDialog.handle_event(msg, params, socket)
    end
  end

  def handle_info(msg, socket) do
    case msg do
      {:lobby, sub_msg} -> ProxyLobby.handle_info(sub_msg, socket)
      {:dialog, sub_msg} -> ProxyDialog.handle_info(sub_msg, socket)
    end
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <.proxy {assigns} />
    """
  end

  # def render_poc(assigns) do
  #   ~H"""
  #   <.live_component
  #     :if={assigns[:actor] && assigns[:server]}
  #     id="users"
  #     module={UserList}
  #     server={@server}
  #     me={@actor.me}
  #     on_click={:proxy_user_list_selects_peer}
  #   />
  #   <.live_component
  #     :if={assigns[:actor] && assigns[:server] && assigns[:dialog_to]}
  #     id="dialog"
  #     module={Dialog}
  #     server={@server}
  #     actor={@actor}
  #     to={@dialog_to}
  #   />
  #   """
  # end

  def handle_info_poc({:proxy_user_list_selects_peer, card}, socket) do
    socket
    |> assign(dialog_to: card)
    |> noreply()
  end
end

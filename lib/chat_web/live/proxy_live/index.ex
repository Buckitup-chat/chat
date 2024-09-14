defmodule ChatWeb.ProxyLive.Index do
  use ChatWeb, :live_view

  alias ChatWeb.ProxyLive.Init
  alias ChatWeb.ProxyLive.Components.Dialog
  alias ChatWeb.ProxyLive.Components.UserList

  embed_templates "*"

  def mount(params, _, socket) do
    [
      &Init.check_connected(&1),
      &Init.extract_actor(&1),
      &Init.extract_address(&1, params)
    ]
    |> Enum.reduce_while(socket, fn step, socket -> step.(socket) end)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <!-- <pre class="bg-white/50"> <%= assigns |> Map.take([:server, :actor]) |> inspect(pretty: true) %></pre> -->
    <.live_component
      :if={assigns[:actor] && assigns[:server]}
      id="users"
      module={UserList}
      server={@server}
      me={@actor.me}
      on_click={:proxy_user_list_selects_peer}
    />
    <.live_component
      :if={assigns[:actor] && assigns[:server] && assigns[:dialog_to]}
      id="dialog"
      module={Dialog}
      server={@server}
      actor={@actor}
      to={@dialog_to}
    />
    """
  end

  def handle_info({:proxy_user_list_selects_peer, card}, socket) do
    socket
    |> assign(dialog_to: card)
    |> noreply()
  end
end

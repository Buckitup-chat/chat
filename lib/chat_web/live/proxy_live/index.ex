defmodule ChatWeb.ProxyLive.Index do
  use ChatWeb, :live_view

  alias ChatWeb.ProxyLive.Init
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
    />
    """
  end
end

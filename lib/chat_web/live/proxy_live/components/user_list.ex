defmodule ChatWeb.ProxyLive.Components.UserList do
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout
  alias ChatWeb.ProxyLive.ChannelClients

  def mount(socket) do
    socket
    |> assign(:users, [])
    |> assign(:loading, true)
    |> ok()
  end

  def update(new_assigns, socket) do
    case new_assigns do
      %{server: server, me: me, id: id} ->
        request_user_list(server, me, id)
        socket |> assign(new_assigns)

      %{new_user: card} ->
        assign(socket, :users, [card | socket.assigns.users] |> Enum.uniq())

      _ ->
        socket |> assign(new_assigns)
    end
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white">
      <div :if={@loading}>
        <h1>Loading users ...</h1>
      </div>
      <div :if={!@loading}>
        <div :for={user <- @users} class="flex flex-row items-center justify-between">
          <Layout.Card.hashed_name card={user} />
        </div>
      </div>
    </div>
    """
  end

  defp request_user_list(server, me, id) do
    component_pid = self()

    Task.start(fn ->
      server
      |> tap(&Proxy.register_me(&1, me))
      |> Proxy.get_users()
      |> then(fn users ->
        if is_list(users) do
          send_update(component_pid, __MODULE__, id: id, users: users, loading: false)
        end
      end)
    end)

    ChannelClients.Users.start_link(
      uri: "ws://#{server}/proxy-socket/websocket",
      on_new_user: fn card ->
        send_update(component_pid, __MODULE__, id: id, new_user: card)
      end
    )
  end
end

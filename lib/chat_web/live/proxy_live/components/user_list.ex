defmodule ChatWeb.ProxyLive.Components.UserList do
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout

  def mount(socket) do
    socket
    |> assign(:users, [])
    |> assign(:loading, true)
    |> ok()
  end

  def update(new_assigns, socket) do
    case new_assigns do
      %{server: server, me: me, id: id} -> request_user_list(server, me, id)
      _ -> :noop
    end

    socket
    |> assign(new_assigns)
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
  end
end

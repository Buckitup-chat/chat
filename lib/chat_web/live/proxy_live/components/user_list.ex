defmodule ChatWeb.ProxyLive.Components.UserList do
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout
  alias ChatWeb.ProxyLive.ChannelClients

  def mount(socket) do
    socket
    |> assign(:users, %{})
    |> assign(:loading, true)
    |> ok()
  end

  def update(new_assigns, socket) do
    new_assigns
    |> case do
      %{server: server, me: me, id: id} ->
        request_user_list(server, me, id)
        new_assigns

      %{users: users} when is_list(users) ->
        new_assigns
        |> Map.drop([:users])
        |> Map.put(:users, Map.new(users, fn card -> {hash_card(card), card} end))

      %{new_user: card} ->
        new_assigns
        |> Map.drop([:new_user])
        |> Map.put(:users, Map.put(socket.assigns.users, hash_card(card), card))

      x ->
        x
    end
    |> then(&assign(socket, &1))
    |> ok()
  end

  def hash_card(card), do: Enigma.short_hash(card)

  def handle_event("user_click", %{"hash" => user_hash}, socket) do
    send_user_clicked(socket.assigns, user_hash)

    noreply(socket)
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white">
      <div :if={@loading}>
        <h1>Loading users ...</h1>
      </div>
      <div :if={!@loading}>
        <div :for={{hash, user} <- @users} class="flex flex-row items-center justify-between">
          <div
            class="cursor-pointer"
            phx-target={@myself}
            phx-click="user_click"
            phx-value-hash={hash}
          >
            <Layout.Card.hashed_name card={user} me={@me} />
          </div>
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

  defp send_user_clicked(assigs, user_hash) do
    card = Map.get(assigs.users, user_hash)
    prefix = assigs[:on_click]

    if card && prefix do
      send(self(), {prefix, card})
    end
  end
end

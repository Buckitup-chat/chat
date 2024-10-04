defmodule ChatWeb.MainLive.Admin.ZerotierSettings do
  @moduledoc "Zerotier settings"
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Admin.ZerotierSettings
  alias Phoenix.LiveView.JS

  @topic Application.compile_env!(:chat, :topic_to_zerotier)

  @impl true
  def mount(socket) do
    request_status()
    request_networks()

    socket
    |> assign(
      status: :loading,
      list: :loading
    )
    |> ok()
  end

  @impl true
  def handle_event("join_network", %{"network" => network_id}, socket) do
    join_network(network_id)
    request_networks()

    socket
    |> assign(:list, :loading)
    |> noreply()
  end

  def handle_event("leave_network", %{"network" => network_id}, socket) do
    leave_network(network_id)
    request_networks()

    socket
    |> assign(:list, :loading)
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.status status={@status} />
      <.networks_list list={@list} target={@myself} />
    </div>
    """
  end

  def status(assigns) do
    ~H"""
    <section class="t-status my-2">
      <label class="text-black/50"> Status: </label>
      <%= if is_map(@status) do %>
        <.status_line
          online={@status["online"]}
          version={@status["version"]}
          client_address={@status["address"]}
        />
      <% else %>
        <%= @status %>...
      <% end %>
    </section>
    """
  end

  def status_line(assigns) do
    ~H"""
    <section class="my-2">
      <%= if @online do %>
        <b>online</b>
      <% else %>
        offline
      <% end %>
      <i><%= @client_address %></i>
      <%= @version %>
    </section>
    """
  end

  def networks_list(assigns) do
    ~H"""
    <section class="t-networks my-2">
      <label class="text-black/50"> Networks: </label>
      <%= if is_list(@list) do %>
        <%= for network <- @list do %>
          <.network_line
            id={network.id}
            name={network.name}
            status={network.status}
            cidrs={network.cidrs}
            target={@target}
          />
        <% end %>
      <% else %>
        <%= @list %>...
      <% end %>
      <.add_network target={@target} />
    </section>
    """
  end

  def network_line(assigns) do
    ~H"""
    <section id={"zerotier-network-#{@id}"} class="my-2 flex space-x-2 justify-between">
      <button
        class="flip hidden items-center justify-center rounded-md px-2 border bg-red-500 border-black/10 mr-1 t-leave-network"
        phx-click={
          JS.toggle(to: "#zerotier-network-#{@id} .flip")
          |> JS.push("leave_network", target: @target)
        }
        phx-value-network={@id}
      >
        Leave!
      </button>
      <%= @name %>
      <span class="flip">
        <%= @cidrs %>
        <%= @status %>
        <button
          phx-click={JS.toggle(to: "#zerotier-network-#{@id} .flip")}
          class="items-center justify-center rounded-md px-2 border bg-red-100 border-black/10"
        >
          Leave
        </button>
      </span>
      <button
        class="flip hidden bg-gray-300 px-2 border rounded-md border-gray-400"
        phx-click={JS.toggle(to: "#zerotier-network-#{@id} .flip")}
      >
        Cancel
      </button>
    </section>
    """
  end

  def add_network(assigns) do
    ~H"""
    <div id="zerotier-add-network">
      <button
        class="flip t-open-new-network-form"
        phx-click={
          JS.toggle(to: "#zerotier-add-network .flip")
          |> JS.focus(to: "#zerotier-add-network input")
        }
      >
        + Add
      </button>
      <form
        class="flip hidden"
        phx-submit={
          JS.push("join_network")
          |> JS.dispatch("click", to: "#zerotier-add-network button[data-clear-form]")
        }
        phx-target={@target}
      >
        <input type="text" placeholder="Network ID" name="network" class="w-full" />
        <div class="flex items-center justify-between my-2">
          <button
            type="button"
            phx-click={JS.toggle(to: "#zerotier-add-network .flip")}
            class="bg-gray-300 px-2 border rounded-md border-gray-400"
          >
            Cancel
          </button>
          <button
            type="submit"
            phx-click={JS.toggle(to: "#zerotier-add-network .flip")}
            class="px-2 border rounded-md border border-white bg-gray-100"
          >
            Join
          </button>
          <button class="hidden" data-clear-form type="reset">Reset</button>
        </div>
      </form>
    </div>
    """
  end

  def parse_info_response(json) do
    json
    |> Jason.decode!()
    |> Map.take(["address", "online", "version"])
  end

  def parse_networks_response(json) do
    json
    |> Jason.decode!()
    |> Enum.map(fn net ->
      %{
        id: net["id"],
        name: net["name"],
        status: net["status"],
        cidrs: net["assignedAddresses"] |> Enum.join(", ")
      }
    end)
  end

  defp request_status do
    pid = self()

    call_command(:info,
      ok: fn response ->
        # coveralls-ignore-start
        status = response |> parse_info_response
        send_update(pid, ZerotierSettings, id: :zerotier_settings, status: status)
        # coveralls-ignore-stop
      end
    )
  end

  defp request_networks do
    pid = self()

    [0, 700, 1500, 5000]
    |> Enum.each(
      &Task.start(fn ->
        Process.sleep(&1)

        call_command(:list_networks,
          ok: fn response ->
            # coveralls-ignore-start
            networks = response |> parse_networks_response
            send_update(pid, ZerotierSettings, id: :zerotier_settings, list: networks)
            # coveralls-ignore-stop
          end
        )
      end)
    )
  end

  defp join_network(network_id) do
    cast_command({:join_network, network_id})
  end

  defp leave_network(network_id) do
    cast_command({:leave_network, network_id})
  end

  defp cast_command(command) do
    Task.start(fn ->
      Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {command, self()})

      receive do
        # coveralls-ignore-next-line
        _ -> :ok
      after
        # coveralls-ignore-next-line
        5000 -> :timeout
      end
    end)
  end

  defp call_command(command, opts) do
    ok = Keyword.fetch!(opts, :ok)
    error = Keyword.get(opts, :error, fn _ -> :error end)

    Task.start(fn ->
      Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {command, self()})

      receive do
        # coveralls-ignore-start
        {^command, {:ok, response}} ->
          ok.(response)

        {^command, {:error, response}} ->
          error.(response)

        _ ->
          :ignore
          # coveralls-ignore-stop
      after
        # coveralls-ignore-next-line
        5000 -> :timeout
      end
    end)
  end
end

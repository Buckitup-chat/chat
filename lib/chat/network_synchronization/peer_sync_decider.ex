defmodule Chat.NetworkSynchronization.PeerSyncDecider do
  @moduledoc "Gates Electric peer sync on device having an admin."

  use GenServer

  alias Chat.NetworkSynchronization
  alias Chat.Pq.OwnerBootstrap

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Chat.PubSub, OwnerBootstrap.topic())

    if OwnerBootstrap.owner() do
      NetworkSynchronization.init_electric_peers()
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:owner_registered, _user_hash}, state) do
    NetworkSynchronization.init_electric_peers()
    {:noreply, state}
  end
end

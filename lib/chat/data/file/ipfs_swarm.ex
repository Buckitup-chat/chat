defmodule Chat.Data.File.IpfsSwarm do
  @moduledoc "Maintains IPFS swarm connections to discovered BuckitUp peers."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File.IpfsStore

  @reconnect_interval :timer.minutes(5)
  @probe_timeout :timer.seconds(10)
  @ipfs_tcp_port 4001

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  def connect_peer(peer_url) when is_binary(peer_url) do
    GenServer.cast(__MODULE__, {:connect_peer, peer_url})
  end

  def disconnect_peer(peer_url) when is_binary(peer_url) do
    GenServer.cast(__MODULE__, {:disconnect_peer, peer_url})
  end

  @impl true
  def init(:ok) do
    schedule_reconnect()
    {:ok, %{peers: %{}}}
  end

  @impl true
  def handle_cast({:connect_peer, peer_url}, state) do
    {:noreply, do_connect(peer_url, state)}
  end

  @impl true
  def handle_cast({:disconnect_peer, peer_url}, state) do
    {:noreply, %{state | peers: Map.delete(state.peers, peer_url)}}
  end

  @impl true
  def handle_info(:reconnect, state) do
    state = reconnect_all(state)
    schedule_reconnect()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp do_connect(peer_url, state) do
    peer_ip = extract_ip(peer_url)

    with {:ok, peer_id} <- probe_ipfs_id(peer_url),
         multiaddr = "/ip4/#{peer_ip}/tcp/#{@ipfs_tcp_port}/p2p/#{peer_id}",
         {_, :ok} <- {:connect, IpfsStore.swarm_connect(multiaddr)} do
      log("IPFS swarm connected: #{peer_url} (#{peer_id})", :debug)
      put_in(state, [:peers, peer_url], %{peer_id: peer_id, multiaddr: multiaddr})
    else
      {:error, reason} ->
        log("IPFS peer ID probe failed for #{peer_url}: #{inspect(reason)}", :debug)
        state

      {:connect, {:error, reason}} ->
        log("IPFS swarm connect failed for #{peer_url}: #{inspect(reason)}", :warning)
        state
    end
  end

  defp reconnect_all(state) do
    connected =
      case IpfsStore.swarm_peers() do
        {:ok, peers} -> MapSet.new(peers, &get_in(&1, ["Peer"]))
        {:error, _} -> MapSet.new()
      end

    state.peers
    |> Enum.reject(fn {_url, %{peer_id: id}} -> MapSet.member?(connected, id) end)
    |> Enum.reduce(state, fn {url, _}, acc -> do_connect(url, acc) end)
  end

  defp probe_ipfs_id(peer_url) do
    url = "#{peer_url}/electric/v1/ipfs/id"

    case Req.get(url, receive_timeout: @probe_timeout) do
      {:ok, %{status: 200, body: %{"peer_id" => id}}} -> {:ok, id}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_ip(peer_url) do
    peer_url |> URI.parse() |> Map.get(:host)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, @reconnect_interval)
  end
end

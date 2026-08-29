defmodule Chat.NetworkSynchronization.Electric.PeerConnector do
  @moduledoc """
  Resolves a peer's PostgreSQL `system_identifier` with exponential backoff,
  then starts `PeerSync` for that peer.

  This is what gets registered under the peer's `via` name (instead of
  `PeerSync` itself), for three reasons:

    - A peer stuck retrying is still "known", so `list_electric_peers/0`
      keeps it out of the LAN rediscovery scan instead of piling up duplicate
      connection attempts every refresh cycle.
    - `PeerSync.init/1` never has to fail: by the time it's started, the
      identifier is already resolved. A transient lookup failure no longer
      risks tripping `ElectricDynamic`'s shared restart-intensity limit,
      which would tear down every other already-connected peer.
    - The identifier lookup (a blocking HTTP call) happens after `start_link`
      returns via `handle_continue`, so discovering several peers at once no
      longer serialises behind each other's network timeouts.
  """

  use GenServer
  use Toolbox.OriginLog

  import Tools.GenServerHelpers

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Electric.PeerIdentifier
  alias Chat.NetworkSynchronization.Electric.PeerSync

  @electric_dynamic Chat.NetworkSynchronization.Supervisor.ElectricDynamic

  @initial_backoff_ms 1_000
  @max_backoff_ms :timer.minutes(5)

  def start_link(opts) do
    peer_url = Keyword.fetch!(opts, :peer_url)
    GenServer.start_link(__MODULE__, peer_url, Keyword.drop(opts, [:peer_url]))
  end

  @doc "Tears down the peer's PeerSync (if running) and stops the connector."
  def disconnect(pid), do: GenServer.call(pid, :disconnect)

  @impl true
  def init(peer_url) do
    %{peer_url: peer_url, backoff: @initial_backoff_ms, peer_sync_pid: nil, connect_timer: nil}
    |> ok_continue(:connect)
  end

  @impl true
  def handle_continue(:connect, state), do: state |> attempt_connect() |> noreply()

  @impl true
  def handle_info(:connect, state), do: state |> attempt_connect() |> noreply()

  def handle_info(
        {:DOWN, _ref, :process, pid, reason},
        %{peer_sync_pid: pid, peer_url: peer_url} = state
      ) do
    log("PeerSync for #{peer_url} exited (#{inspect(reason)}), reconnecting", :warning)

    %{state | peer_sync_pid: nil, backoff: @initial_backoff_ms}
    |> attempt_connect()
    |> noreply()
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: state |> noreply()

  @impl true
  def handle_call(:disconnect, _from, %{peer_sync_pid: peer_sync_pid} = state) do
    if peer_sync_pid, do: DynamicSupervisor.terminate_child(@electric_dynamic, peer_sync_pid)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def terminate(_reason, %{connect_timer: connect_timer}) do
    if connect_timer, do: Process.cancel_timer(connect_timer)
    :ok
  end

  defp attempt_connect(%{peer_url: peer_url} = state) do
    case PeerIdentifier.fetch_system_identifier(peer_url) do
      {:ok, system_identifier} -> start_peer_sync(state, system_identifier)
      {:error, reason} -> retry(state, "system_identifier lookup failed (#{inspect(reason)})")
    end
  end

  defp start_peer_sync(%{peer_url: peer_url} = state, system_identifier) do
    case DynamicSupervisor.start_child(
           @electric_dynamic,
           {PeerSync, peer_url: peer_url, system_identifier: system_identifier}
         ) do
      {:ok, pid} ->
        Process.monitor(pid)
        log("PeerSync connected for #{peer_url}", :info)
        NetworkSynchronization.notify_sync_source_peer_connected(peer_url)
        %{state | peer_sync_pid: pid, backoff: @initial_backoff_ms, connect_timer: nil}

      {:error, reason} ->
        retry(state, "failed to start PeerSync (#{inspect(reason)})")
    end
  end

  defp retry(%{peer_url: peer_url, backoff: backoff} = state, why) do
    log("PeerConnector #{peer_url}: #{why}, retrying in #{backoff}ms", :warning)

    %{
      state
      | backoff: min(backoff * 2, @max_backoff_ms),
        connect_timer: Process.send_after(self(), :connect, backoff)
    }
  end
end

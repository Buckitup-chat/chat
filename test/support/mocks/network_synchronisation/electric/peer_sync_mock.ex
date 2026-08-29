defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.PeerSyncMock do
  @moduledoc """
  Stand-in for PeerSync in PeerConnector tests. Notifies the test pid
  (registered under `:peer_connector_test_pid`) with its own pid on start,
  so the test can assert on it and kill it to simulate PeerSync exiting.
  """

  use GenServer

  def start_link(opts) do
    peer_url = Keyword.fetch!(opts, :peer_url)
    system_identifier = Keyword.fetch!(opts, :system_identifier)
    GenServer.start_link(__MODULE__, {peer_url, system_identifier})
  end

  @impl true
  def init({peer_url, system_identifier}) do
    notify({:peer_sync_started, self(), peer_url, system_identifier})
    {:ok, %{}}
  end

  defp notify(msg) do
    case Application.get_env(:chat, :peer_connector_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end

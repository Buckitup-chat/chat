defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.PeerIdentifierMock do
  @moduledoc """
  PeerIdentifier mock for PeerConnector tests.

  Results are popped in order from an `Agent` registered under
  `:peer_connector_test_results_agent` in the application env — see
  `PeerConnectorTest` for setup. Each call also notifies the test pid
  registered under `:peer_connector_test_pid`.
  """

  def fetch_system_identifier(peer_url) do
    notify({:identifier_fetch_attempted, peer_url})

    Application.get_env(:chat, :peer_connector_test_results_agent)
    |> Agent.get_and_update(fn
      [result | rest] -> {result, rest}
      [] -> {{:error, :no_more_test_results}, []}
    end)
  end

  defp notify(msg) do
    case Application.get_env(:chat, :peer_connector_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end

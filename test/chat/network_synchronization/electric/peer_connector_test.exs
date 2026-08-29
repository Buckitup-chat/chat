defmodule Chat.NetworkSynchronization.Electric.PeerConnectorTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.NetworkSynchronization.Electric.PeerConnector

  @electric_dynamic Chat.NetworkSynchronization.Supervisor.ElectricDynamic
  @peer_url "http://10.0.0.9"
  @system_identifier "test_system_id"

  rewire(PeerConnector, [
    {Chat.NetworkSynchronization.Electric.PeerIdentifier,
     ChatSupport.Mocks.NetworkSynchronization.Electric.PeerIdentifierMock},
    {Chat.NetworkSynchronization.Electric.PeerSync,
     ChatSupport.Mocks.NetworkSynchronization.Electric.PeerSyncMock}
  ])

  setup do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    Application.put_env(:chat, :peer_connector_test_pid, self())
    Application.put_env(:chat, :peer_connector_test_results_agent, agent)

    on_exit(fn ->
      Application.delete_env(:chat, :peer_connector_test_pid)
      Application.delete_env(:chat, :peer_connector_test_results_agent)
    end)

    :ok
  end

  test "connects immediately when identifier resolves on first try" do
    set_results([{:ok, @system_identifier}])

    {:ok, _connector} = start_supervised({PeerConnector, peer_url: @peer_url})

    assert_receive {:identifier_fetch_attempted, @peer_url}, 500
    assert_receive {:peer_sync_started, pid, @peer_url, @system_identifier}, 500

    cleanup_peer_sync(pid)
  end

  test "retries with backoff when identifier lookup fails, then succeeds" do
    set_results([{:error, :timeout}, {:ok, @system_identifier}])

    {:ok, _connector} = start_supervised({PeerConnector, peer_url: @peer_url})

    assert_receive {:identifier_fetch_attempted, @peer_url}, 500
    refute_receive {:peer_sync_started, _, _, _}, 200

    assert_receive {:identifier_fetch_attempted, @peer_url}, 1500
    assert_receive {:peer_sync_started, pid, @peer_url, @system_identifier}, 500

    cleanup_peer_sync(pid)
  end

  test "reconnects with reset backoff when PeerSync exits" do
    set_results([{:ok, @system_identifier}, {:ok, @system_identifier}])

    {:ok, connector} = start_supervised({PeerConnector, peer_url: @peer_url})

    assert_receive {:peer_sync_started, first_pid, @peer_url, @system_identifier}, 500
    assert %{backoff: 1_000} = :sys.get_state(connector)

    Process.exit(first_pid, :kill)

    assert_receive {:identifier_fetch_attempted, @peer_url}, 500
    assert_receive {:peer_sync_started, second_pid, @peer_url, @system_identifier}, 500
    assert second_pid != first_pid
    assert %{backoff: 1_000} = :sys.get_state(connector)

    cleanup_peer_sync(second_pid)
  end

  test "disconnect/1 terminates PeerSync and stops the connector" do
    set_results([{:ok, @system_identifier}])

    {:ok, connector} = start_supervised({PeerConnector, peer_url: @peer_url})

    assert_receive {:peer_sync_started, peer_sync_pid, @peer_url, @system_identifier}, 500

    ref = Process.monitor(connector)
    assert :ok = PeerConnector.disconnect(connector)

    assert_receive {:DOWN, ^ref, :process, ^connector, :normal}, 500
    refute Process.alive?(peer_sync_pid)
  end

  defp set_results(results) do
    Application.get_env(:chat, :peer_connector_test_results_agent)
    |> Agent.update(fn _ -> results end)
  end

  # Cleans up the mock PeerSync this test caused to be started under the
  # real, globally-named ElectricDynamic supervisor.
  defp cleanup_peer_sync(pid) do
    DynamicSupervisor.terminate_child(@electric_dynamic, pid)
  end
end

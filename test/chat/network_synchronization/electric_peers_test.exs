defmodule ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs do
  @moduledoc false

  defmodule Owner do
    @moduledoc false
    def owner, do: :owner
  end

  defmodule NoUnit do
    @moduledoc false
    def unit, do: raise("no default unit")
  end

  defmodule Worker do
    @moduledoc false
    use Agent

    def start_link(opts), do: Agent.start_link(fn -> opts[:source] end, name: opts[:name])
  end

  defmodule PeerConnector do
    @moduledoc false
    use Agent, restart: :transient

    def start_link(opts), do: Agent.start_link(fn -> opts[:peer_url] end, name: opts[:name])
    def disconnect(pid), do: Agent.stop(pid, :normal)
  end
end

defmodule ChatTest.NetworkSynchronization.ElectricPeersTest do
  use ExUnit.Case, async: true

  import Rewire

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Store
  alias ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs

  rewire(Store, source_db_prefix: S9, source_table: S9, status_table: T9)
  rewire(Store, source_db_prefix: S9, source_table: S9, status_table: T9, as: StoreMock)

  rewire(NetworkSynchronization,
    Store: StoreMock,
    Worker: ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs.Worker,
    OwnerBootstrap: ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs.Owner,
    PeerConnector: ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs.PeerConnector,
    registry: R9,
    dynamic_supervisor: D9,
    electric_dynamic: ED9,
    electric_registry: ER9
  )

  rewire(NetworkSynchronization,
    PeerConnector: ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs.PeerConnector,
    Default: ChatTest.NetworkSynchronization.ElectricPeersTest.Stubs.NoUnit,
    electric_dynamic: ED9,
    electric_registry: ER9,
    as: NoUnitSynchronization
  )

  setup do
    start_supervised!({DynamicSupervisor, name: D9, strategy: :one_for_one}, id: D9)
    start_supervised!({Registry, name: R9, keys: :unique}, id: R9)
    start_supervised!({DynamicSupervisor, name: ED9, strategy: :one_for_one}, id: ED9)
    start_supervised!({Registry, name: ER9, keys: :unique}, id: ER9)
    Store.init()
    :ok
  end

  describe "source with a peer url" do
    test "start connects the electric peer, stop disconnects it" do
      source = source_with_url("http://10.1.2.3:4000/sync")

      NetworkSynchronization.start_source(source.id)
      assert NetworkSynchronization.list_electric_peers() == ["http://10.1.2.3:4000"]

      NetworkSynchronization.stop_source(source.id)
      assert_peers([])

      NetworkSynchronization.remove_source(source.id)
    end

    test "unparsable url gets no electric peer" do
      source = source_with_url("not a url")

      NetworkSynchronization.start_source(source.id)
      assert NetworkSynchronization.list_electric_peers() == []

      NetworkSynchronization.stop_source(source.id)
      NetworkSynchronization.remove_source(source.id)
    end

    test "init_electric_peers connects only started sources" do
      started =
        source_with_url("http://10.1.2.4:4000") |> struct(started?: true) |> Store.update_source()

      stopped = source_with_url("http://10.1.2.5:4000")

      NetworkSynchronization.init_electric_peers()
      assert NetworkSynchronization.list_electric_peers() == ["http://10.1.2.4:4000"]

      Enum.each([started, stopped], &NetworkSynchronization.remove_source(&1.id))
    end
  end

  describe "electric peers" do
    test "removing an unknown peer is not found" do
      assert {:error, :not_found} =
               NetworkSynchronization.remove_electric_peer("http://10.9.9.9:1")
    end

    test "peer is removed even without a default storage unit" do
      {:ok, pid} = NoUnitSynchronization.add_electric_peer("http://10.1.2.6:4000")

      assert :ok = NoUnitSynchronization.remove_electric_peer("http://10.1.2.6:4000")
      refute Process.alive?(pid)
      assert_peers([])
    end
  end

  # Helpers

  defp source_with_url(url) do
    NetworkSynchronization.add_source()
    |> Map.fetch!(:id)
    |> NetworkSynchronization.update_source(url: url)
  end

  defp assert_peers(expected) do
    Support.RetryHelper.retry_until(500, fn ->
      assert NetworkSynchronization.list_electric_peers() == expected
    end)
  end
end

defmodule ChatTest.NetworkSynchronization.PeerSyncDeciderTest do
  use ExUnit.Case, async: false
  import Rewire

  alias Chat.AdminDb
  alias Chat.Pq.OwnerBootstrap

  defmodule MockNS do
    def init_electric_peers do
      :ets.update_counter(:psd_test_calls, :init, 1, {:init, 0})
    end
  end

  rewire(Chat.NetworkSynchronization.PeerSyncDecider,
    NetworkSynchronization: MockNS,
    as: TestDecider
  )

  setup do
    if :ets.whereis(:psd_test_calls) != :undefined, do: :ets.delete(:psd_test_calls)
    :ets.new(:psd_test_calls, [:named_table, :public, :set])

    CubDB.delete(AdminDb.db(), :pq_admin)
    on_exit(fn -> CubDB.delete(AdminDb.db(), :pq_admin) end)
    :ok
  end

  defp init_call_count do
    case :ets.lookup(:psd_test_calls, :init) do
      [{:init, count}] -> count
      [] -> 0
    end
  end

  test "does not init electric peers when no admin" do
    start_supervised!({TestDecider, name: :psd_test_no_admin})
    Process.sleep(50)
    assert init_call_count() == 0
  end

  test "inits electric peers when admin present" do
    AdminDb.put_new(:pq_admin, %{user_hash: "test", sign_pkey: "test"})
    start_supervised!({TestDecider, name: :psd_test_with_admin})
    Process.sleep(50)
    assert init_call_count() > 0
  end

  test "inits electric peers on owner_registered broadcast" do
    start_supervised!({TestDecider, name: :psd_test_broadcast})
    Process.sleep(50)
    assert init_call_count() == 0

    Phoenix.PubSub.broadcast(Chat.PubSub, OwnerBootstrap.topic(), {:owner_registered, "hash"})
    Process.sleep(50)
    assert init_call_count() > 0
  end
end

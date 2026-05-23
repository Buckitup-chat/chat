defmodule Chat.NetworkSynchronization.Electric.DeferredStoreRefetchTest do
  use ExUnit.Case, async: true, group: :ets_deferred

  import Rewire

  alias Chat.Data.Schemas.UserStorage
  alias Chat.NetworkSynchronization.Electric.DeferredRecord

  rewire(Chat.NetworkSynchronization.Electric.DeferredStore, [
    {Electric.Client,
     ChatSupport.Mocks.NetworkSynchronization.Electric.DeferredElectricClientMock},
    {Chat.NetworkSynchronization.Electric.ShapeWriter,
     ChatSupport.Mocks.NetworkSynchronization.Electric.ShapeWriterMock},
    {:as, RewiredDeferredStore}
  ])

  @peer_url "http://10.0.0.1:4444"

  setup do
    Application.put_env(:chat, :deferred_test_pid, self())
    Application.put_env(:chat, :deferred_mock_messages, [])
    Application.put_env(:chat, :consumer_test_pid, self())

    {:ok, pid} = RewiredDeferredStore.start_link(name: :test_deferred_refetch)

    on_exit(fn ->
      Process.exit(pid, :normal)
      Application.delete_env(:chat, :deferred_test_pid)
      Application.delete_env(:chat, :deferred_mock_messages)
      Application.delete_env(:chat, :consumer_test_pid)
      Application.delete_env(:chat, :consumer_test_write_result)
    end)

    :ok
  end

  describe "trigger_redeliver/1" do
    test "refetches from /electric/v1/shapes endpoint" do
      redeliver_deferred(:user_storage, user_hash: "h1", uuid: "u1")

      assert_receive {:client_created, endpoint}, 1000
      assert endpoint == "#{@peer_url}/electric/v1/shapes"
    end

    test "passes Ecto query with WHERE matching the primary key" do
      redeliver_deferred(:user_storage, user_hash: "h1", uuid: "u1")

      assert_receive {:stream_called, _endpoint, query, opts}, 1000
      assert opts == [live: false, replica: :full]
      assert %Ecto.Query{} = query
      assert query.from.source == {"user_storage", UserStorage}
    end

    test "replays fetched change through ShapeWriter" do
      storage = %UserStorage{user_hash: "h1", uuid: "u1"}
      Application.put_env(:chat, :deferred_mock_messages, [change_message(storage)])

      redeliver_deferred(:user_storage, user_hash: "h1", uuid: "u1")

      assert_receive {:write_called, :user_storage, :insert, ^storage, _opts}, 1000
    end
  end

  defp redeliver_deferred(shape, key) do
    record = %DeferredRecord{
      shape: shape,
      key: key,
      operation: :insert,
      missing_parents: [{:user_card, key[:user_hash]}],
      peer_url: @peer_url,
      deferred_at: System.monotonic_time(:millisecond)
    }

    GenServer.cast(:test_deferred_refetch, {:redeliver, [record]})
  end

  defp change_message(value) do
    %Electric.Client.Message.ChangeMessage{headers: %{operation: :insert}, value: value}
  end
end

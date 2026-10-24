defmodule Chat.ReviewBot.GcServerTest do
  use ExUnit.Case, async: false
  import Rewire

  @now 1_700_000_000
  @tombstone_grace div(:timer.hours(24 * 3 * 7), 1000)

  defmodule FakeTimeKeeper do
    def now_unix, do: 1_700_000_000
  end

  defmodule FakeReviewWriteToken do
    def hard_delete_old_tombstones(threshold_ts) do
      send(:gc_server_test, {:hard_deleted, threshold_ts})
      {0, nil}
    end

    def pending_expired_tokens(origin_hash, threshold_ts) do
      send(:gc_server_test, {:queried_pending, origin_hash, threshold_ts})
      []
    end
  end

  defmodule FakeOriginSetting do
    def get_review_token_ttl_days(_), do: 7
  end

  defmodule FakeGC do
    def soft_delete_tokens(tokens, bot_hash) do
      send(:gc_server_test, {:gc_ran, bot_hash, length(tokens)})
    end
  end

  defmodule FakeWorker do
    def info(_bot_hash), do: %{origin_hash: "u_origin"}
  end

  setup do
    Process.register(self(), :gc_server_test)

    on_exit(fn ->
      try do
        Process.unregister(:gc_server_test)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  test "calls hard_delete_old_tombstones with correct threshold on :clean" do
    server =
      rewire(Chat.ReviewBot.GcServer,
        TimeKeeper: FakeTimeKeeper,
        ReviewWriteToken: FakeReviewWriteToken
      )

    {:ok, pid} = server.start_link([])
    send(pid, :clean)

    expected_threshold = @now - @tombstone_grace
    assert_receive {:hard_deleted, ^expected_threshold}, 500

    GenServer.stop(pid)
  end

  test "runs GC for all registered bots on :gc_tick" do
    start_supervised!({Registry, keys: :unique, name: Chat.ReviewBot.Registry})

    Registry.register(Chat.ReviewBot.Registry, "u_bot1", nil)

    server =
      rewire(Chat.ReviewBot.GcServer,
        TimeKeeper: FakeTimeKeeper,
        ReviewWriteToken: FakeReviewWriteToken,
        OriginSetting: FakeOriginSetting,
        GarbageCollector: FakeGC,
        Worker: FakeWorker
      )

    {:ok, pid} = server.start_link([])
    send(pid, :gc_tick)

    assert_receive {:queried_pending, "u_origin", _threshold}, 500
    assert_receive {:gc_ran, "u_bot1", 0}, 500

    GenServer.stop(pid)
  end
end

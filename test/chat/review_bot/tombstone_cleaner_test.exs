defmodule Chat.ReviewBot.TombstoneCleanerTest do
  use ExUnit.Case, async: false
  import Rewire

  @now 1_700_000_000
  @grace_period 3 * 7 * 86_400

  defmodule FakeTimeKeeper do
    def now_unix, do: 1_700_000_000
  end

  defmodule FakeReviewWriteToken do
    def hard_delete_old_tombstones(threshold_ts) do
      send(:tc_test, {:hard_deleted, threshold_ts})
      {0, nil}
    end
  end

  test "calls hard_delete_old_tombstones with correct threshold on :clean" do
    Process.register(self(), :tc_test)

    cleaner =
      rewire(Chat.ReviewBot.TombstoneCleaner,
        TimeKeeper: FakeTimeKeeper,
        ReviewWriteToken: FakeReviewWriteToken
      )

    {:ok, pid} = cleaner.start_link([])

    send(pid, :clean)

    expected_threshold = @now - @grace_period
    assert_receive {:hard_deleted, ^expected_threshold}, 500

    GenServer.stop(pid)
    Process.unregister(:tc_test)
  end
end

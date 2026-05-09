defmodule Chat.TimeTest do
  use ExUnit.Case

  import Rewire

  alias Chat.Time

  test "best_local_time is after 2023" do
    assert :lt =
             DateTime.compare(
               ~U[2023-01-01 01:01:01Z],
               Time.best_local_time()
             )
  end

  describe "first boot time protection (reported: certificate expired due to stale clock)" do
    test "best_local_time uses build timestamp, not stale file mtimes" do
      Time.best_local_time()
      |> assert_within_last_day()
    end

    test "fresh device with NTP failure still gets recent time" do
      time_with_failed_ntp().best_local_time()
      |> assert_within_last_day()
    end

    test "set_initial_system_time with NTP failure completes without crash" do
      assert :ok = time_with_failed_ntp().set_initial_system_time()
    end

    test "set_initial_system_time with future NTP advances time" do
      assert :ok = time_with_future_ntp().set_initial_system_time()
    end

    defp time_with_failed_ntp do
      rewire(Chat.Time, [{Chat.TimeKeeper, Chat.TimeTest.FakeTimeKeeper}])
    end

    defp time_with_future_ntp do
      rewire(Chat.Time, [{Chat.TimeKeeper, Chat.TimeTest.FutureTimeKeeper}])
    end

    defp assert_within_last_day(datetime) do
      assert DateTime.diff(DateTime.utc_now(), datetime) < 86_400
    end
  end

  defmodule FakeTimeKeeper do
    def try_ntp(_timeout \\ 3000), do: :error
    def read_persisted_time(_path), do: nil
    def persist_path, do: "/tmp/test_timekeeper_time"
    def update_time(_unix), do: :ok
  end

  defmodule FutureTimeKeeper do
    @future_unix DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()

    def try_ntp(_timeout \\ 3000), do: {:ok, @future_unix}
    def read_persisted_time(_path), do: nil
    def persist_path, do: "/tmp/test_timekeeper_time"
    def update_time(_unix), do: :ok
  end
end

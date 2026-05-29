defmodule Chat.TimeTest do
  use ExUnit.Case, async: true

  import Rewire

  alias Chat.TimeKeeper

  test "best_local_time is after 2023" do
    assert :lt =
             DateTime.compare(
               ~U[2023-01-01 01:01:01Z],
               TimeKeeper.best_local_time()
             )
  end

  describe "first boot time protection (reported: certificate expired due to stale clock)" do
    test "best_local_time uses build timestamp, not stale file mtimes" do
      result = TimeKeeper.best_local_time()

      beam_path =
        case :code.which(Chat.TimeKeeper) do
          :cover_compiled ->
            Application.app_dir(:chat, "ebin")
            |> Path.join("Elixir.Chat.TimeKeeper.beam")

          path ->
            to_string(path)
        end

      compile_time =
        beam_path
        |> File.stat!(time: :posix)
        |> Map.get(:mtime)

      assert DateTime.to_unix(result) >= compile_time - 2
      assert DateTime.compare(result, DateTime.utc_now()) != :gt
    end

    test "best_local_time includes persist file mtime" do
      path = Chat.TimeTest.FakeSource.persist_path()
      File.write!(path, "0")

      keeper = rewire(Chat.TimeKeeper, [{Chat.TimeKeeper.Source, Chat.TimeTest.FakeSource}])

      %{mtime: mtime} = File.lstat!(path, time: :posix)

      result_unix = keeper.best_local_time() |> DateTime.to_unix()
      assert result_unix >= mtime
    after
      File.rm(Chat.TimeTest.FakeSource.persist_path())
    end

    test "set_initial_system_time with NTP failure completes without crash" do
      assert :ok = keeper_with_failed_ntp().set_initial_system_time()
    end

    test "set_initial_system_time with future NTP advances time" do
      assert :ok = keeper_with_future_ntp().set_initial_system_time()
    end

    defp keeper_with_failed_ntp do
      rewire(Chat.TimeKeeper, [{Chat.TimeKeeper.Source, Chat.TimeTest.FakeSource}])
    end

    defp keeper_with_future_ntp do
      rewire(Chat.TimeKeeper, [{Chat.TimeKeeper.Source, Chat.TimeTest.FutureSource}])
    end
  end

  defmodule FakeSource do
    def try_ntp(_timeout \\ 3000), do: :error
    def read_persisted_time(_path), do: nil
    def persist_path, do: "/tmp/test_timekeeper_time"
  end

  defmodule FutureSource do
    @future_unix DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()

    def try_ntp(_timeout \\ 3000), do: {:ok, @future_unix}
    def read_persisted_time(_path), do: nil
    def persist_path, do: "/tmp/test_timekeeper_time"
  end
end

defmodule Chat.TimeKeeperTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Rewire

  alias Chat.TimeKeeper

  @moduletag :tmp_dir
  @pt_key {TimeKeeper, :offset}
  @future_unix 4_000_000_000
  @future_date_string "2096-10-02 07:06:40"

  defmodule NtpOk do
    def persist_path, do: Process.get(:persist_path)
    def try_ntp, do: {:ok, 4_000_000_000}
    def read_persisted_time(_path), do: nil
  end

  defmodule NtpDown do
    def persist_path, do: Process.get(:persist_path)
    def try_ntp, do: :error
    defdelegate read_persisted_time(path), to: Chat.TimeKeeper.Source
  end

  defmodule DateOk do
    def cmd("date", ["-u", "-s", time]), do: {send(self(), {:date_set, time}), 0}
    defdelegate monotonic_time(unit), to: System
    defdelegate os_time(unit), to: System
  end

  defmodule DateFails do
    def cmd("date", _args), do: {"date: cannot set date: Operation not permitted\n", 1}
    defdelegate monotonic_time(unit), to: System
    defdelegate os_time(unit), to: System
  end

  setup %{tmp_dir: dir} do
    saved_offset = :persistent_term.get(@pt_key, nil)
    path = Path.join(dir, "timekeeper_time")
    Process.put(:persist_path, path)

    on_exit(fn -> restore_offset(saved_offset) end)

    %{
      path: path,
      state: %{offset: TimeKeeper.monotonic_offset(), persist_path: path, persist_timer: nil}
    }
  end

  describe "clock reads" do
    test "now/0 and now_unix/0 follow the stored offset" do
      :persistent_term.put(@pt_key, TimeKeeper.monotonic_offset(@future_unix))

      assert_in_delta @future_unix, TimeKeeper.now_unix(), 1
      assert_in_delta @future_unix, TimeKeeper.now() |> DateTime.to_unix(), 1
      assert_in_delta @future_unix, TimeKeeper.monotonic_to_unix(TimeKeeper.monotonic_offset()), 1
    end

    test "fall back to the system clock without a stored offset" do
      :persistent_term.erase(@pt_key)
      system_unix = DateTime.utc_now() |> DateTime.to_unix()

      assert_in_delta system_unix, TimeKeeper.now_unix(), 1
      assert_in_delta system_unix, TimeKeeper.monotonic_to_unix(TimeKeeper.monotonic_offset()), 1
    end
  end

  describe "update_time" do
    test "moves the offset forward and persists the new time", %{path: path, state: state} do
      {:noreply, updated} = TimeKeeper.handle_cast({:update_time, @future_unix}, state)

      assert_in_delta @future_unix, TimeKeeper.monotonic_to_unix(updated.offset), 1
      assert updated.offset == :persistent_term.get(@pt_key)
      assert "#{@future_unix}" == File.read!(path)
    end

    test "stays monotonic when an older time arrives", %{path: path, state: state} do
      {:noreply, ahead} = TimeKeeper.handle_cast({:update_time, @future_unix}, state)
      {:noreply, after_older} = TimeKeeper.handle_cast({:update_time, @future_unix - 3600}, ahead)

      assert ahead == after_older
      assert "#{@future_unix}" == File.read!(path)
    end

    test "ignores times behind the current clock", %{path: path, state: state} do
      assert {:noreply, ^state} = TimeKeeper.handle_cast({:update_time, 1_000}, state)
      refute File.exists?(path)
    end

    test "logs when the time can't be persisted", %{tmp_dir: dir, state: state} do
      state = %{state | persist_path: Path.join([dir, "missing", "time"])}

      log =
        capture_log(fn -> TimeKeeper.handle_cast({:update_time, @future_unix}, state) end)

      assert log =~ "persist failed"
    end

    test "set_time/1 accepts naive and UTC datetimes from clients" do
      past = ~U[2020-01-01 00:00:00Z]
      before = :sys.get_state(TimeKeeper)

      assert :ok = past |> DateTime.to_naive() |> TimeKeeper.set_time()
      assert :ok = TimeKeeper.set_time(past)
      assert before == :sys.get_state(TimeKeeper)
    end
  end

  describe "process" do
    test "init/1 seeds the offset from the system clock" do
      {:ok, state} = TimeKeeper.init([])
      Process.cancel_timer(state.persist_timer)

      assert_in_delta DateTime.utc_now() |> DateTime.to_unix(), TimeKeeper.now_unix(), 1
      assert state.offset == :persistent_term.get(@pt_key)
      assert "priv/timekeeper_time" == state.persist_path
    end

    test "persists the current time periodically", %{path: path, state: state} do
      {:noreply, %{persist_timer: timer}} = TimeKeeper.handle_info(:persist, state)
      Process.cancel_timer(timer)

      assert_in_delta TimeKeeper.monotonic_to_unix(state.offset),
                      path |> File.read!() |> String.to_integer(),
                      1
    end

    test "ignores unknown messages", %{state: state} do
      assert {:noreply, ^state} = TimeKeeper.handle_info(:unknown, state)
    end
  end

  describe "set_initial_system_time/0" do
    test "leaves the OS clock alone unless allowed" do
      assert :ok = rewire(TimeKeeper, Source: NtpOk).set_initial_system_time()
    end

    test "sets the OS clock when allowed" do
      with_set_time(fn ->
        assert :ok = rewire(TimeKeeper, Source: NtpOk, System: DateOk).set_initial_system_time()
      end)

      assert_received {:date_set, @future_date_string}
    end

    test "reports a failing OS clock" do
      log =
        capture_log(fn ->
          with_set_time(fn ->
            assert :error =
                     rewire(TimeKeeper, Source: NtpOk, System: DateFails).set_initial_system_time()
          end)
        end)

      assert log =~ "can't set system clock to '#{@future_date_string}': 1"
    end

    test "falls back to the persisted time without NTP", %{path: path} do
      File.write!(path, "#{@future_unix}")

      with_set_time(fn ->
        assert :ok = rewire(TimeKeeper, Source: NtpDown, System: DateOk).set_initial_system_time()
      end)

      assert_received {:date_set, @future_date_string}
    end

    test "falls back to local file times without NTP or persisted time" do
      with_set_time(fn ->
        assert :ok = rewire(TimeKeeper, Source: NtpDown, System: DateOk).set_initial_system_time()
      end)

      refute_received {:date_set, _}
    end
  end

  defp with_set_time(fun) do
    Application.put_env(:chat, :set_time, true)
    fun.()
  after
    Application.delete_env(:chat, :set_time)
  end

  test "best_local_time/0 trusts the newest persist file timestamp", %{path: path} do
    File.touch!(path, @future_unix)

    assert DateTime.from_unix!(@future_unix) ==
             rewire(TimeKeeper, Source: NtpDown).best_local_time()
  end

  defp restore_offset(nil), do: :persistent_term.erase(@pt_key)
  defp restore_offset(offset), do: :persistent_term.put(@pt_key, offset)
end

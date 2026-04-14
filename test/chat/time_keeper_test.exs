defmodule Chat.TimeKeeperTest do
  use ExUnit.Case, async: false

  alias Chat.TimeKeeper

  @pt_key {TimeKeeper, :offset}

  setup do
    old = :persistent_term.get(@pt_key, nil)

    on_exit(fn ->
      case GenServer.whereis(TimeKeeper) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 1_000)
      end

      if old, do: :persistent_term.put(@pt_key, old), else: safe_erase(@pt_key)
    end)

    safe_erase(@pt_key)
    :ok
  end

  defp safe_erase(key) do
    :persistent_term.erase(key)
  rescue
    ArgumentError -> :ok
  end

  # --- monotonic_offset fallback ---

  test "monotonic_offset/0 computes offset when persistent_term is empty" do
    offset = TimeKeeper.monotonic_offset()
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    reconstructed = System.monotonic_time(:second) + offset

    assert_in_delta reconstructed, now_unix, 2
  end

  test "monotonic_offset/0 returns stored value when persistent_term is set" do
    :persistent_term.put(@pt_key, 42)

    assert TimeKeeper.monotonic_offset() == 42
  end

  # --- now/now_unix without GenServer ---

  test "now_unix/0 falls back to wall clock when no offset stored" do
    unix = TimeKeeper.now_unix()
    wall = DateTime.utc_now() |> DateTime.to_unix()

    assert_in_delta unix, wall, 2
  end

  test "now_unix/0 uses stored offset" do
    expected_unix = 1_700_000_000
    offset = expected_unix - System.monotonic_time(:second)
    :persistent_term.put(@pt_key, offset)

    assert_in_delta TimeKeeper.now_unix(), expected_unix, 2
  end

  test "now/0 returns DateTime consistent with now_unix/0" do
    expected_unix = 1_700_000_000
    offset = expected_unix - System.monotonic_time(:second)
    :persistent_term.put(@pt_key, offset)

    dt = TimeKeeper.now()

    assert_in_delta DateTime.to_unix(dt), expected_unix, 2
  end

  # --- GenServer lifecycle ---

  test "start_link sets persistent_term offset" do
    {:ok, pid} = TimeKeeper.start_link()
    assert Process.alive?(pid)

    offset = :persistent_term.get(@pt_key)
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    assert_in_delta System.monotonic_time(:second) + offset, now_unix, 2
  end

  # --- update_time ---

  test "update_time advances offset when given future timestamp" do
    {:ok, _pid} = TimeKeeper.start_link()
    initial_offset = :persistent_term.get(@pt_key)

    future = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600)
    TimeKeeper.update_time(future)
    Process.sleep(50)

    new_offset = :persistent_term.get(@pt_key)

    assert new_offset > initial_offset
    assert_in_delta System.monotonic_time(:second) + new_offset, future, 2
  end

  test "update_time ignores past timestamps" do
    {:ok, _pid} = TimeKeeper.start_link()
    initial_offset = :persistent_term.get(@pt_key)

    past = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.-(3600)
    TimeKeeper.update_time(past)
    Process.sleep(50)

    assert :persistent_term.get(@pt_key) == initial_offset
  end

  test "update_time is no-op when GenServer is not running" do
    assert TimeKeeper.update_time(1_700_000_000) == :ok
  end

  # --- persist / read_persisted_time ---

  test "persist timer writes current time to file" do
    path = Path.join(System.tmp_dir!(), "timekeeper_test_#{:erlang.unique_integer([:positive])}")

    on_exit(fn -> File.rm(path) end)

    Application.put_env(:chat, :timekeeper_path, path)
    {:ok, pid} = TimeKeeper.start_link()

    send(pid, :persist)
    Process.sleep(50)

    assert {:ok, content} = File.read(path)
    unix = content |> String.trim() |> String.to_integer()

    assert_in_delta unix, DateTime.utc_now() |> DateTime.to_unix(), 2
  after
    Application.put_env(:chat, :timekeeper_path, "priv/timekeeper_time")
  end

  test "read_persisted_time parses valid file" do
    path = Path.join(System.tmp_dir!(), "timekeeper_read_#{:erlang.unique_integer([:positive])}")
    unix = 1_700_000_000
    File.write!(path, Integer.to_string(unix))

    on_exit(fn -> File.rm(path) end)

    dt = TimeKeeper.read_persisted_time(path)

    assert %DateTime{} = dt
    assert DateTime.to_unix(dt) == unix
  end

  test "read_persisted_time returns nil for missing file" do
    assert TimeKeeper.read_persisted_time("/tmp/nonexistent_#{:rand.uniform(999_999)}") == nil
  end

  test "read_persisted_time returns nil for garbage content" do
    path =
      Path.join(System.tmp_dir!(), "timekeeper_garbage_#{:erlang.unique_integer([:positive])}")

    File.write!(path, "not_a_number")

    on_exit(fn -> File.rm(path) end)

    assert TimeKeeper.read_persisted_time(path) == nil
  end

  # --- NTP ---

  test "try_ntp returns {:ok, unix} or :error" do
    result = TimeKeeper.try_ntp(500)

    case result do
      {:ok, unix} ->
        now = DateTime.utc_now() |> DateTime.to_unix()
        assert_in_delta unix, now, 5

      :error ->
        :ok
    end
  end

  # --- multiple update_time calls converge ---

  test "successive update_time calls keep the latest" do
    {:ok, _pid} = TimeKeeper.start_link()

    base = DateTime.utc_now() |> DateTime.to_unix()

    TimeKeeper.update_time(base + 100)
    Process.sleep(20)
    TimeKeeper.update_time(base + 200)
    Process.sleep(20)
    TimeKeeper.update_time(base + 50)
    Process.sleep(20)

    assert_in_delta TimeKeeper.now_unix(), base + 200, 2
  end

  # --- persist survives across restart ---

  test "persisted time survives GenServer restart" do
    path =
      Path.join(System.tmp_dir!(), "timekeeper_restart_#{:erlang.unique_integer([:positive])}")

    on_exit(fn -> File.rm(path) end)

    Application.put_env(:chat, :timekeeper_path, path)

    {:ok, pid} = TimeKeeper.start_link()

    future = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(7200)
    TimeKeeper.update_time(future)
    Process.sleep(20)

    send(pid, :persist)
    Process.sleep(50)

    GenServer.stop(pid, :normal)

    dt = TimeKeeper.read_persisted_time(path)
    assert_in_delta DateTime.to_unix(dt), future, 2
  after
    Application.put_env(:chat, :timekeeper_path, "priv/timekeeper_time")
  end
end

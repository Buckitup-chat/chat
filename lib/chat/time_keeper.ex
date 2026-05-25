defmodule Chat.TimeKeeper do
  @moduledoc """
  Maintains accurate time on devices without a battery-backed RTC.

  On boot, tries NTP briefly, then falls back to a persisted time file,
  then to file mtime heuristics. Sets system clock ONCE at boot.

  After boot, tracks time as a monotonic offset. LiveView clients and
  shape writers call `update_time/1` to refine the offset without
  touching the system clock (avoiding Postgrex pool disruption).

  All non-Ecto code should use `now/0` or `now_unix/0` instead of
  `DateTime.utc_now()`.
  """

  use GenServer

  use Toolbox.OriginLog

  alias Chat.Db
  alias Chat.TimeKeeper.Source

  @persist_interval :timer.minutes(3)
  @build_timestamp System.os_time(:second)
  @pt_key {__MODULE__, :offset}

  # --- Public API (lock-free reads via :persistent_term) ---

  @doc "Current time as DateTime. Replaces `DateTime.utc_now()`."
  def now do
    now_unix()
    |> DateTime.from_unix!()
  end

  @doc "Current time as unix seconds."
  def now_unix do
    case :persistent_term.get(@pt_key, nil) do
      nil -> DateTime.utc_now() |> DateTime.to_unix()
      offset -> System.monotonic_time(:second) + offset
    end
  end

  @doc "Current global monotonic offset."
  def monotonic_offset do
    :persistent_term.get(@pt_key, nil) ||
      monotonic_offset(DateTime.utc_now() |> DateTime.to_unix())
  end

  @doc "Compute monotonic offset from a unix timestamp."
  def monotonic_offset(unix_timestamp) do
    unix_timestamp - System.monotonic_time(:second)
  end

  @doc "Convert a monotonic offset back to unix seconds."
  def monotonic_to_unix(offset) do
    System.monotonic_time(:second) + offset
  end

  @doc "Accept a time update from a client. Updates offset only if newer."
  def update_time(unix_timestamp) when is_integer(unix_timestamp) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:update_time, unix_timestamp})
    end
  end

  # --- Boot-time API (callable before GenServer starts) ---

  @doc """
  Set system time on first boot. Tries NTP, falls back to persisted time
  or DB file mtimes. Only advances the clock forward.

  Ensure that your vm.args allows for timewarps:

    `+C multi_time_warp`
  """
  def set_initial_system_time do
    @build_timestamp
    |> DateTime.from_unix!()
    |> advance_system_time()

    path = Source.persist_path()

    case Source.try_ntp() do
      {:ok, unix} ->
        log("NTP time acquired", :info)
        DateTime.from_unix!(unix)

      :error ->
        best_known_time(path)
    end
    |> advance_system_time()
  end

  @doc "Accept a DateTime from a client and update the offset."
  def set_time(%NaiveDateTime{} = time) do
    time
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
    |> update_time()
  end

  def set_time(%DateTime{} = time) do
    time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_unix()
    |> update_time()
  end

  @doc false
  def best_local_time do
    [db_time(), persist_file_time(), static_time()]
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
    |> Enum.max()
    |> DateTime.from_unix!()
  end

  # --- GenServer ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    path = Source.persist_path()

    offset =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> monotonic_offset()

    :persistent_term.put(@pt_key, offset)

    timer = Process.send_after(self(), :persist, @persist_interval)

    log("started, offset=#{offset}", :info)

    {:ok, %{offset: offset, persist_path: path, persist_timer: timer}}
  end

  @impl true
  def handle_cast({:update_time, unix_timestamp}, state) do
    current_unix = System.monotonic_time(:second) + state.offset

    if unix_timestamp > current_unix do
      new_offset = monotonic_offset(unix_timestamp)
      :persistent_term.put(@pt_key, new_offset)

      persist_time(unix_timestamp, state.persist_path)

      ["offset updated, delta=", Integer.to_string(unix_timestamp - current_unix), "s"]
      |> log(:debug)

      {:noreply, %{state | offset: new_offset}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:persist, state) do
    unix = System.monotonic_time(:second) + state.offset

    persist_time(unix, state.persist_path)

    timer = Process.send_after(self(), :persist, @persist_interval)
    {:noreply, %{state | persist_timer: timer}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp persist_time(unix, path) do
    case File.write(path, Integer.to_string(unix)) do
      :ok -> :ok
      {:error, reason} -> log("persist failed: #{inspect(reason)}", :warning)
    end
  end

  defp best_known_time(path) do
    persisted = Source.read_persisted_time(path)
    decided = best_local_time()

    [persisted, decided]
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> decided end)
  end

  defp advance_system_time(%DateTime{} = time) do
    case DateTime.compare(time, DateTime.utc_now()) do
      :gt ->
        time
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_string()
        |> set_system_time()

      _ ->
        :ok
    end
  end

  defp set_system_time(string_time) do
    case Application.get_env(:chat, :set_time, false) do
      true ->
        set_os_clock(string_time)

      false ->
        log(["Set clock to ", string_time, " UTC"], :debug)
        :ok
    end
  end

  defp set_os_clock(string_time) do
    case System.cmd("date", ["-u", "-s", string_time]) do
      {_result, 0} ->
        log(["system clock set to ", string_time, " UTC"], :info)
        :ok

      {message, code} ->
        log(
          [
            "can't set system clock to '",
            string_time,
            "': ",
            Integer.to_string(code),
            " ",
            inspect(message)
          ],
          :error
        )

        :error
    end
  end

  defp persist_file_time do
    Source.persist_path()
    |> path_time()
  end

  defp db_time do
    "#{Db.file_path()}/*.cub"
    |> path_time()
  end

  defp static_time, do: [@build_timestamp]

  defp path_time(wildcard) do
    wildcard
    |> Path.wildcard()
    |> Enum.map(fn file ->
      %{atime: atime, mtime: mtime, ctime: ctime} = file |> File.lstat!(time: :posix)

      [atime, mtime, ctime]
      |> Enum.max()
    end)
    |> then(fn
      [] -> nil
      x -> x
    end)
  end
end

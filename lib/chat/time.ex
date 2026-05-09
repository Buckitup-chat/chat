defmodule Chat.Time do
  @moduledoc "Time manipulation helpers as RPi has no offline internal clock"
  require Logger

  alias Chat.Db

  @build_timestamp System.os_time(:second)

  def best_local_time do
    (db_time() || static_time())
    |> Enum.max()
    |> DateTime.from_unix!()
  end

  def set_initial_system_time do
    @build_timestamp
    |> DateTime.from_unix!()
    |> advance_system_time()

    path = Chat.TimeKeeper.persist_path()

    case Chat.TimeKeeper.try_ntp() do
      {:ok, unix} ->
        Logger.info("[Time] NTP time acquired")
        DateTime.from_unix!(unix)

      :error ->
        best_known_time(path)
    end
    |> advance_system_time()
  end

  @doc """
  Ensure that your vm.args allows for timewarps. If it doesn't, nerves_time will update the OS system time, but Erlang's system time will lag.
  The following line should be in the beginning or middle of the vm.args file:

    `+C multi_time_warp`

  """
  def set_time(%NaiveDateTime{} = time) do
    time
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
    |> Chat.TimeKeeper.update_time()
  end

  def set_time(%DateTime{} = time) do
    time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_unix()
    |> Chat.TimeKeeper.update_time()
  end

  def monotonic_offset(unix_timestamp) do
    unix_timestamp - System.monotonic_time(:second)
  end

  def monotonic_to_unix(monotonic_offset) do
    System.monotonic_time(:second) + monotonic_offset
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
        Logger.debug(["Set clock to ", string_time, " UTC"])
        :ok
    end
  end

  defp set_os_clock(string_time) do
    case System.cmd("date", ["-u", "-s", string_time]) do
      {_result, 0} ->
        Logger.info(["nerves_time set system clock to ", string_time, " UTC"])
        :ok

      {message, code} ->
        Logger.error([
          "nerves_time can't set system clock to '",
          string_time,
          "': ",
          Integer.to_string(code),
          " ",
          inspect(message)
        ])

        :error
    end
  end

  defp best_known_time(path) do
    persisted = Chat.TimeKeeper.read_persisted_time(path)
    decided = best_local_time()

    [persisted, decided]
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> decided end)
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

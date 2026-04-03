defmodule Chat.Time do
  @moduledoc "Time manipulation helpers as RPi has no offline internal clock"
  require Logger

  alias Chat.Db

  def decide_time do
    if time = db_time() do
      time
    else
      static_time()
    end
    |> Enum.max()
    |> DateTime.from_unix!()
  end

  def init_time do
    path = Chat.TimeKeeper.persist_path()

    case Chat.TimeKeeper.try_ntp() do
      {:ok, unix} ->
        Logger.info("[Time] NTP time acquired")
        DateTime.from_unix!(unix)

      :error ->
        persisted = Chat.TimeKeeper.read_persisted_time(path)
        decided = decide_time()

        [persisted, decided]
        |> Enum.reject(&is_nil/1)
        |> Enum.max_by(&DateTime.to_unix/1, fn -> decided end)
    end
    |> set_system_time_once()
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

  defp set_system_time_once(%DateTime{} = time) do
    string_time =
      time
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.to_naive()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_string()

    if Application.get_env(:chat, :set_time, false) do
      set_system_time(string_time)
    else
      Logger.debug(["Set clock to ", string_time, " UTC"])
      :ok
    end
  end

  defp set_system_time(string_time) do
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

  defp db_time do
    "#{Db.file_path()}/*.cub"
    |> path_time()
  end

  defp static_time do
    Application.app_dir(:chat)
    |> Path.join("priv/static")
    |> then(&"#{&1}/*")
    |> path_time
  end

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

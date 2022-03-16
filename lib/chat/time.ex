defmodule Chat.Time do
  require Logger

  alias Chat.Db

  def init_time do
    unless time = db_time() do
      static_time()
    else
      time
    end
    |> Enum.max()
    |> DateTime.from_unix!()
    |> set_time()
  end

  @doc """
  Ensure that your vm.args allows for timewarps. If it doesn't, nerves_time will update the OS system time, but Erlang's system time will lag.
  The following line should be in the beginning or middle of the vm.args file:

    `+C multi_time_warp`

  """
  def set_time(%NaiveDateTime{} = time) do
    if NaiveDateTime.compare(time, NaiveDateTime.utc_now()) == :gt do
      string_time = time |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()

      if Application.get_env(:chat, :set_time, false) do
        set_system_time(string_time)
      else
        Logger.debug("Set clock to #{string_time} UTC")
        :ok
      end
    end
  end

  def set_time(%DateTime{} = time) do
    time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> set_time()
  end

  defp set_system_time(string_time) do
    case System.cmd("date", ["-u", "-s", string_time]) do
      {_result, 0} ->
        Logger.info("nerves_time set system clock to #{string_time} UTC")
        :ok

      {message, code} ->
        Logger.error(
          "nerves_time can't set system clock to '#{string_time}': #{code} #{inspect(message)}"
        )

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

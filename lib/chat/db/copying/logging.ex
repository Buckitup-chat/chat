defmodule Chat.Db.Copying.Logging do
  @moduledoc """
  Logging functions for Copying
  This can be enabled by config.
  """
  require Logger

  @enabled? Application.compile_env(:chat, :db_write_logging, false)

  def log_copying(from, to, keys) do
    {chunks, data} = keys |> Enum.split_with(&match?({:file_chunk, _, _, _}, &1))

    [
      "file_chunks: ",
      inspect(chunks |> Enum.count()),
      " + data: ",
      inspect(data |> Enum.count())
    ]
    |> log_dbs({from, to}, :info)
  end

  def log_finished(from, to) do
    ["is done"]
    |> log_dbs({from, to}, :info)
  end

  def log_restart_on_stuck(from, to, progress) do
    progress_dump =
      progress
      |> Map.update(:data_keys, [], &Enum.take(&1, 10))
      |> Map.update(:file_keys, [], &Enum.take(&1, 10))
      |> inspect(pretty: true)

    [
      "stuck. restarting... ",
      progress_dump
    ]
    |> log_dbs({from, to}, :debug)
  end

  def log_copying_ignored(from, to) do
    ["is ignored. Another copying is in progress"]
    |> log_dbs({from, to}, :warning)
  end

  if @enabled? do
    def log_written_in(nil, _), do: :ok
    def log_written_in([], _), do: :ok

    def log_written_in(keys, db) do
      [
        " -> ",
        inspect(db),
        inspect(keys)
      ]
      |> log(:debug)
    end
  else
    def log_written_in(_keys, _db), do: :ok
  end

  defp log_dbs(msg, {from, to}, level) do
    [
      inspect(from),
      " -> ",
      inspect(to),
      " ",
      msg
    ]
    |> log(level)
  end

  defp log(msg, level) do
    Logger.log(level, ["[copying] ", msg])
  end
end

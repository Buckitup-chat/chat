defmodule Chat.Db.Copying.Logging do
  @moduledoc """
  Logging functions for Copying
  This can be enabled by config.
  """
  @enabled? Application.compile_env(:chat, :copying_logging, false)

  if @enabled? do
    require Logger

    def log_copying(from, to, keys) do
      {chunks, data} = keys |> Enum.split_with(&match?({:file_chunk, _, _, _}, &1))

      [
        "[copying] ",
        inspect(from),
        " -> ",
        inspect(to),
        " file_chunks: ",
        inspect(chunks |> Enum.count()),
        " + data: ",
        inspect(data |> Enum.count())
      ]
      |> Logger.info()
    end

    def log_finished(from, to) do
      [
        "[copying] ",
        inspect(from),
        " -> ",
        inspect(to),
        " is done"
      ]
      |> Logger.debug()
    end

    def log_restart_on_stuck(from, to, progress) do
      progress_dump =
        progress
        |> Map.update(:data_keys, [], &Enum.take(&1, 10))
        |> Map.update(:file_keys, [], &Enum.take(&1, 10))
        |> inspect(pretty: true)

      [
        "[copying] ",
        inspect(from),
        " -> ",
        inspect(to),
        " stuck. restarting... ",
        progress_dump
      ]
      |> Logger.debug()
    end

    def log_copying_ignored(from, to) do
      [
        "[copying] ",
        inspect(from),
        " -> ",
        inspect(to),
        " is ignored. Another copying is in progress"
      ]
      |> Logger.warn()
    end

    def log_written_in(nil, _), do: :ok
    def log_written_in([], _), do: :ok

    def log_written_in(keys, db) do
      [
        "[copying] ",
        " -> ",
        inspect(db),
        inspect(keys)
      ]
      |> Logger.debug()
    end
  else
    def log_copying(_from, _to, _keys), do: :ok
    def log_finished(_from, _to), do: :ok
    def log_restart_on_stuck(_from, _to, _progress), do: :ok
    def log_copying_ignored(_from, _to), do: :ok
    def log_written_in(_keys, _db), do: :ok
  end
end

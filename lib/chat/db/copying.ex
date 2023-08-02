defmodule Chat.Db.Copying do
  @moduledoc """
  Manages difference copying between DBs with WriteQeue streams
  """
  require Logger

  import Chat.Db.WriteQueue.ReadStream

  alias Chat.Db.Common
  alias Chat.Db.Copying.Progress
  alias Chat.Db.Scope.Full, as: FullScope
  alias Chat.Db.WriteQueue

  def await_copied(from, to, keys_set \\ nil) do
    "[copying] reading DBs" |> Logger.debug()
    to_queue = Common.names(to, :queue)
    stream = stream(from, to, nil, keys_set)
    stream_keys = read_stream(stream, :keys)

    log_copying(from, to, stream_keys)

    stream |> WriteQueue.put_stream(to_queue)

    Progress.new(stream_keys, to)
    |> ensure_complete()
    |> case do
      :done ->
        log_finished(from, to)
        :ok

      {:stuck, progress} ->
        log_restart_on_stuck(from, to, progress)
        force_copied(from, to, Progress.get_unwritten_keys(progress) |> Enum.shuffle())
    end
  end

  defp force_copied(from, to, keys_set) do
    "[copying] reading DBs" |> Logger.debug()
    to_queue = Common.names(to, :queue)
    stream = stream(from, to, nil, keys_set)
    stream_keys = read_stream(stream, :keys)

    log_copying(from, to, stream_keys)

    stream |> WriteQueue.force_stream(to_queue)

    Progress.new(stream_keys, to)
    |> ensure_complete()
    |> case do
      :done ->
        log_finished(from, to)
        :ok

      {:stuck, progress} ->
        log_restart_on_stuck(from, to, progress)
        force_copied(from, to, Progress.get_unwritten_keys(progress) |> Enum.shuffle())
    end
  end

  defp ensure_complete(prev_progress, stuck_for_ms \\ 0) do
    progress = Progress.eliminate_written(prev_progress)
    # {time, progress} = :timer.tc(fn -> Progress.eliminate_written(prev_progress) end)
    # time |> IO.inspect(label: "time")

    cond do
      Progress.complete?(progress) ->
        :done

      stuck_for_ms > 40_000 ->
        {:stuck, progress}

      true ->
        prev_count = Progress.left_keys(prev_progress)
        count = Progress.left_keys(progress)
        changed? = prev_count > count

        delay = Progress.recheck_delay_in_ms(progress)
        Process.sleep(delay)

        if !changed? and stuck_for_ms > 10_000 do
          Logger.debug(inspect({prev_count, count, stuck_for_ms, delay}))
        end

        ensure_complete(
          progress,
          if(changed?, do: 0, else: stuck_for_ms + delay)
        )
    end
  end

  defp log_copying(from, to, keys) do
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

  defp log_finished(from, to) do
    [
      "[copying] ",
      inspect(from),
      " -> ",
      inspect(to),
      " is done"
    ]
    |> Logger.debug()
  end

  defp log_restart_on_stuck(from, to, progress) do
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

  defp stream(from, to, awaiter, keys_set)

  defp stream(from, to, awaiter, nil) do
    [from, to]
    |> Stream.map(fn db ->
      Task.async(fn -> FullScope.keys(db) end)
    end)
    |> Enum.to_list()
    |> Task.await_many(:timer.hours(1))
    |> then(fn [src, dst] ->
      keys =
        src
        |> MapSet.difference(dst)
        |> MapSet.to_list()

      read_stream_new(from, keys, awaiter)
    end)
  end

  defp stream(from, to, awaiter, %MapSet{} = src) do
    dst = FullScope.keys(to)

    keys =
      src
      |> MapSet.difference(dst)
      |> MapSet.to_list()

    read_stream(keys: keys, db: from, awaiter: awaiter)
  end

  defp stream(from, to, awaiter, keys_list) when is_list(keys_list) do
    stream(from, to, awaiter, MapSet.new(keys_list))
  end
end

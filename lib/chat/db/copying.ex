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
      :done -> :ok
      {:stuck, progress} -> await_copied(from, to, Progress.get_unwritten_keys(progress))
    end
    |> tap(fn _ -> log_finished(from, to) end)
  end

  defp ensure_complete(prev_progress, started? \\ false, stuck_for_ms \\ 0) do
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

        Logger.debug(inspect({prev_count, count, stuck_for_ms, delay, started?}))

        if !changed? do
          progress
          |> Map.drop([:file_keys, :data_keys])
          |> inspect(pretty: true)
          |> Logger.warning()
        end

        ensure_complete(
          progress,
          started? or changed?,
          (started? && !changed? && stuck_for_ms + delay) || 0
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

defmodule Chat.Db.Copying do
  @moduledoc """
  Manages difference copying between DBs with WriteQeue streams
  """
  require Logger

  import Chat.Db.WriteQueue.ReadStream

  alias Chat.Db.ChangeTracker
  alias Chat.Db.Common
  alias Chat.Db.WriteQueue

  def await_copied(from, to, keys \\ nil) do
    to_pipe = Common.names(to)

    stream = stream(from, to, nil, keys)

    awaiter =
      Task.async(fn ->
        stream
        |> read_stream(:keys)
        |> ChangeTracker.await_many(:timer.hours(1))
      end)

    stream
    |> read_stream(awaiter: awaiter.pid)
    |> WriteQueue.put_stream(to_pipe.queue)

    Task.await(awaiter, :infinity)
  end

  defp stream(from, to, awaiter, keys)

  defp stream(from, to, awaiter, nil) do
    [from, to]
    |> Stream.map(fn db ->
      Task.async(fn -> get_data_keys_set(db) end)
    end)
    |> Enum.to_list()
    |> Task.await_many(:timer.hours(1))
    |> then(fn [src, dst] ->
      keys =
        src
        |> MapSet.difference(dst)
        |> MapSet.to_list()

      read_stream(keys: keys, db: from, awaiter: awaiter)
    end)
  end

  defp stream(from, to, awaiter, src) do
    dst = get_data_keys_set(to)

    keys =
      src
      |> MapSet.difference(dst)
      |> MapSet.to_list()

    read_stream(keys: keys, db: from, awaiter: awaiter)
  end

  defp get_data_keys_set(db) do
    CubDB.with_snapshot(db, fn snap ->
      {snap, MapSet.new()}
      |> before_change_tracking()
      |> after_change_tracking_till_chunk_keys()
      |> chunk_keys()
      |> after_chunk_keys_till_file_chunks()
      |> after_file_chunks()
      |> elem(1)
    end)
  end

  defp chunk_keys({snap, set}) do
    CubDB.Snapshot.select(snap, min_key: {:chunk_key, nil}, max_key: {:chunk_key, ""})
    |> Stream.map(fn {{_, file_chunk_key} = k, _v} -> [k, file_chunk_key] end)
    |> Enum.to_list()
    |> List.flatten()
    |> MapSet.new()
    |> MapSet.union(set)
    |> then(&{snap, &1})
  end

  defp before_change_tracking(keys) do
    keys |> join_keys_of(max_key: {:change_tracking_marker, 0}, max_key_inclusive: false)
  end

  defp after_change_tracking_till_chunk_keys(keys) do
    keys
    |> join_keys_of(
      min_key: {:"change_tracking_marker\0", 0},
      max_key: {:chunk_key, 0},
      max_key_inclusive: false
    )
  end

  defp after_chunk_keys_till_file_chunks(keys) do
    keys
    |> join_keys_of(
      min_key: {:chunk_key, ""},
      max_key: {:file_chunk, nil, nil, nil},
      max_key_inclusive: false
    )
  end

  defp after_file_chunks(keys) do
    keys
    |> join_keys_of(min_key: {:"file_chunk\0", 0, 0, 0})
  end

  defp join_keys_of({snap, set}, select_opts) do
    CubDB.Snapshot.select(snap, select_opts)
    |> Stream.map(fn {k, _v} -> k end)
    |> MapSet.new()
    |> MapSet.union(set)
    |> then(&{snap, &1})
  end
end

defmodule Chat.Db.Copying do
  @moduledoc """
  Manages difference copying between DBs with WriteQeue streams
  """
  require Logger

  import Chat.Db.WriteQueue.ReadStream

  alias Chat.Db.ChangeTracker
  alias Chat.Db.Common
  alias Chat.Db.WriteQueue
  alias Chat.FileFs

  def await_copied(from, to, keys \\ nil) do
    to_queue = Common.names(to, :queue)

    stream = stream(from, to, nil, keys)

    awaiter =
      Task.async(fn ->
        stream
        |> read_stream(:keys)
        |> ChangeTracker.await_many(:timer.hours(1))
      end)

    stream
    |> read_stream(awaiter: awaiter.pid)
    |> WriteQueue.put_stream(to_queue)

    Task.await(awaiter, :infinity)
    to |> CubDB.file_sync()
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

      read_stream_new(from, keys, awaiter)
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

  def get_data_keys_set(db) do
    CubDB.with_snapshot(db, fn snap ->
      {snap, MapSet.new()}
      |> before_change_tracking()
      |> after_change_tracking_till_chunk_keys()
      |> chunk_keys()
      |> after_chunk_keys_till_file_chunks()
      |> after_file_chunks()
      |> elem(1)
    end)
    |> join_fs_keys(db)
  end

  defp chunk_keys({_snap, _set} = keys) do
    keys |> join_keys_of(min_key: {:chunk_key, nil}, max_key: {:chunk_key, ""})
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

  defp join_fs_keys(keys, db) do
    db
    |> CubDB.data_dir()
    |> then(&"#{&1}_files")
    |> FileFs.relative_filenames()
    |> Enum.map(&filename_to_chunk_key/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.union(keys)
  end

  defp filename_to_chunk_key(<<
         _::binary-size(3),
         hash::binary-size(64),
         ?/,
         start::binary-size(20),
         ?/,
         finish::binary-size(20)
       >>) do
    {
      :file_chunk,
      hash |> Base.decode16!(case: :lower),
      start |> String.to_integer(),
      finish |> String.to_integer()
    }
  end

  defp filename_to_chunk_key(_), do: nil
end

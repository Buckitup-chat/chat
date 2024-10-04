defmodule Chat.Db.WriteQueue.ReadStream do
  @moduledoc """
  List of keys to be read from db and yielded into queue
  """

  require Logger
  require Record

  alias Chat.Db.Common
  alias Chat.Db.WriteQueue.FileReader

  Record.defrecord(:read_stream,
    db: nil,
    keys: [],
    file_readers: [],
    file_ready: nil,
    awaiter: nil,
    skip_set: nil
  )

  def read_stream_new(db, keys, awaiter \\ nil, skip_set \\ nil) do
    read_stream(db: db, keys: keys, awaiter: awaiter, skip_set: skip_set)
  end

  def set_awaiter(read_stream(awaiter: nil) = stream, awaiter) do
    read_stream(stream, awaiter: awaiter)
  end

  def read_stream_empty?(read_stream(keys: [_ | _])), do: false
  def read_stream_empty?(read_stream(file_readers: [_ | _])), do: false
  def read_stream_empty?(read_stream(file_ready: {_, _})), do: false

  def read_stream_empty?(read_stream(awaiter: pid)) when is_pid(pid) do
    send(pid, :done)
    true
  end

  def read_stream_empty?(_), do: true

  def read_stream_yield(
        read_stream(file_ready: {_, _} = data, file_readers: readers, db: db) = stream
      ) do
    {next_file, next_readers} = FileReader.yield_file(file_reader(db), readers)

    {[data],
     read_stream(stream,
       file_ready: next_file,
       file_readers: next_readers
     )}
  end

  def read_stream_yield(
        read_stream(
          db: db,
          keys: list,
          awaiter: awaiter,
          file_readers: readers,
          skip_set: skip_set
        ) = stream
      ) do
    {data, new_readers, new_list} = read_list(db, readers, list, skip_set)

    if new_list == [] and new_readers == [] and awaiter do
      send(awaiter, :done)
    end

    db_pid = Process.whereis(db)

    {next_file, updated_readers} =
      if is_pid(db_pid) and Process.alive?(db_pid) do
        FileReader.yield_file(file_reader(db), new_readers)
      else
        {nil, new_readers}
      end

    {data,
     read_stream(stream,
       keys: new_list,
       file_readers: updated_readers,
       file_ready: next_file
     )}
  end

  defp read_list(db, readers, list, skip_set) do
    {keys, new_list} = take_portion(list, [], 100)
    db_pid = Process.whereis(db)
    true = is_pid(db_pid) and Process.alive?(db_pid)
    files_path = CubDB.data_dir(db) <> "_files"
    file_reader = file_reader(db)

    {file_keys, db_keys} =
      Enum.split_with(keys, fn
        {:file_chunk, _, _, _} -> true
        _ -> false
      end)

    new_readers =
      readers ++ Enum.map(file_keys, &FileReader.add_task(file_reader, &1, files_path, skip_set))

    data =
      db_keys
      |> Enum.map(&{&1, CubDB.get(db, &1)})

    {data, new_readers, new_list}
  rescue
    # in case source DB is dead we finish with the stream
    e ->
      e |> inspect(pretty: true) |> Logger.warning()
      # Process.info(self(), :current_stacktrace) |> inspect(pretty: true) |> Logger.warn()
      # {db, list |> Enum.take(10), readers} |> inspect(pretty: true) |> Logger.warn()
      {[], [], []}
  end

  defp take_portion(list, keys, limit) do
    case {list, limit} do
      {[], _} -> {keys, list}
      {_, l} when l <= 0 -> {keys, list}
      {[{:file_chunk, _, _, _} = key | rest], _} -> take_portion(rest, [key | keys], limit - 40)
      {[key | rest], _} -> take_portion(rest, [key | keys], limit - 1)
    end
  end

  defp file_reader(db), do: Common.names(db, :file_reader)
end

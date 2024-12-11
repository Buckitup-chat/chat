defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """

  import Chat.Db.Common

  alias Chat.Db.Queries
  alias Chat.Db.WriteQueue
  alias Chat.Db.WriteQueue.FileReader

  @db_version "v.10.1"
  @db_location Application.compile_env(:chat, :cub_db_file, "priv/db")

  def list(range, transform), do: Queries.list(db(), range, transform)
  def list({_min, _max} = range), do: Queries.list(db(), range)
  def select({_min, _max} = range, amount), do: Queries.select(db(), range, amount)
  def values({_min, _max} = range, amount), do: Queries.values(db(), range, amount)
  def get_max_one(min, max), do: Queries.get_max_one(db(), min, max)
  def get(key), do: Queries.get(db(), key)
  def get_next(key, max_key, predicate), do: Queries.get_next(db(), key, max_key, predicate)
  def get_prev(key, min_key, predicate), do: Queries.get_prev(db(), key, min_key, predicate)
  def has_key?(key), do: Queries.has_key?(db(), key)

  def put(key, value), do: WriteQueue.put({key, value}, queue())

  def delete(key),
    do: WriteQueue.mark_delete(key, queue())

  def bulk_delete({_min, _max} = range),
    do: WriteQueue.mark_delete(range, queue())

  def put_chunk(data) do
    WriteQueue.put_chunk(data, queue())
  end

  def db do
    get_chat_db_env(:data_pid)
  end

  def queue, do: :data_queue |> get_chat_db_env()

  def supervise(db_name, path) do
    %{
      status: dry_relay_name,
      queue: queue_name,
      read_supervisor: read_supervisor,
      file_reader: file_reader_name,
      writer: writer_name,
      compactor: compactor,
      decider: decider,
      write_supervisor: write_supervisor
    } = names(db_name)

    [
      # read supervisor
      {Task.Supervisor, name: read_supervisor},
      # file reader
      {FileReader, name: file_reader_name, read_supervisor: read_supervisor},
      # queue
      {Chat.Db.WriteQueue, name: queue_name},
      # db
      %{
        id: db_name,
        start:
          {CubDB, :start_link,
           [path, [auto_file_sync: false, auto_compact: false, name: db_name]]}
      },
      # dry status relay
      %{
        id: dry_relay_name,
        start: {Agent, :start_link, [fn -> false end, [name: dry_relay_name]]}
      },
      # write supervisor
      {DynamicSupervisor,
       name: write_supervisor,
       strategy: :one_for_one,
       max_restarts: 1,
       max_seconds: :timer.minutes(30)},
      # decider
      {Chat.Db.Pipeline.Decider,
       name: decider,
       queue: queue_name,
       writer: writer_name,
       compactor: compactor,
       status_relay: dry_relay_name,
       write_supervisor: write_supervisor,
       db: db_name,
       files_path: path <> "_files"}
    ]
  end

  def file_path do
    data_dir = Application.get_env(:chat, :cub_db_file, "priv/data")
    "#{data_dir}/#{@db_version}"
  end

  def version_path, do: @db_version
end

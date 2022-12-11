defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  require Logger

  import Chat.Db.Common

  alias Chat.Db.Queries
  alias Chat.Db.WriteQueue

  @db_version "v.8"
  @db_location Application.compile_env(:chat, :cub_db_file, "priv/db")

  def list(range, transform), do: Queries.list(db(), range, transform)
  def list({_min, _max} = range), do: Queries.list(db(), range)
  def select({_min, _max} = range, amount), do: Queries.select(db(), range, amount)
  def values({_min, _max} = range, amount), do: Queries.values(db(), range, amount)
  def get_max_one(min, max), do: Queries.get_max_one(db(), min, max)
  def get(key), do: Queries.get(db(), key)
  def get_next(key, max_key, predicate), do: Queries.get_next(db(), key, max_key, predicate)
  def get_prev(key, min_key, predicate), do: Queries.get_prev(db(), key, min_key, predicate)

  def put(key, value) do
    case key do
      {:action_log, _, _} -> WriteQueue.put({key, value}, queue())
      {:change_tracking_marker, _} -> WriteQueue.put({key, value}, queue())
      _ -> WriteQueue.push({key, value}, queue())
    end
  end

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
      writer: writer_name
    } = names(db_name)

    [
      # queue
      {Chat.Db.WriteQueue, name: queue_name},
      # db
      %{
        id: db_name,
        start:
          {CubDB, :start_link,
           [path, [auto_file_sync: false, auto_compact: false, name: db_name]]}
      },
      # dry status realy
      %{
        id: dry_relay_name,
        start: {Agent, :start_link, [fn -> false end, [name: dry_relay_name]]}
      },
      # writer
      {Chat.Db.QueueWriter.Process,
       name: writer_name, db: db_name, queue: queue_name, status_relay: dry_relay_name}
    ]
  end

  def file_path do
    "#{@db_location}/#{@db_version}"
  end

  def version_path, do: @db_version
end

defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  require Logger

  use GenServer

  alias Chat.Db.Maintenance
  alias Chat.Db.ModeManager
  alias Chat.Db.Pids
  alias Chat.Db.Queries

  @db_version "v.7"
  @db_location Application.compile_env(:chat, :cub_db_file, "priv/db")

  def list(range, transform), do: Queries.list(db(), range, transform)
  def list({_min, _max} = range), do: Queries.list(db(), range)
  def select({_min, _max} = range, amount), do: Queries.select(db(), range, amount)
  def values({_min, _max} = range, amount), do: Queries.values(db(), range, amount)
  def get_max_one(min, max), do: Queries.get_max_one(db(), min, max)
  def get(key), do: Queries.get(db(), key)
  def get_next(key, max_key, predicate), do: Queries.get_next(db(), key, max_key, predicate)
  def get_prev(key, min_key, predicate), do: Queries.get_prev(db(), key, min_key, predicate)

  def put(key, value), do: Queries.put(db(), key, value)
  def delete(key), do: Queries.delete(db(), key)
  def bulk_delete({_min, _max} = range), do: Queries.bulk_delete(db(), range)

  #
  # GenServer interface
  #

  def db do
    __MODULE__
    |> GenServer.call(:db)
  end

  def file_db do
    __MODULE__
    |> GenServer.call(:file_db)
  end

  def writable? do
    __MODULE__
    |> GenServer.call(:writable?)
  end

  def swap_pid(new_pids) do
    __MODULE__
    |> GenServer.call({:swap, new_pids})
  end

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    Chat.Time.init_time()
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, db} = CubDB.start_link(file_path(), auto_file_sync: true)
    {:ok, file_db} = CubDB.start_link(file_db_path(), auto_file_sync: false, auto_compact: false)

    {:ok, {%Pids{main: db, file: file_db}, 100}}
  end

  @impl true
  def handle_call(:db, _from, {%Pids{main: pid}, _} = state) do
    {:reply, pid, state}
  end

  def handle_call(:file_db, _from, {%Pids{file: pid}, _} = state) do
    {:reply, pid, state}
  end

  def handle_call(:writable?, _from, {_, writable_size} = state) do
    {:reply, writable_size > 0, state}
  end

  def handle_call({:swap, %Pids{} = new}, _from, {%Pids{} = old, writable_size}) do
    {:reply, old, {new, writable_size}}
  end

  @impl true
  def handle_info({:writable_size, bytes}, {%Pids{} = pids, _}),
    do: {:noreply, {pids, bytes}}

  #
  # Extra logic
  #

  def file_path do
    "#{@db_location}/#{@db_version}"
  end

  def file_db_path do
    "#{@db_location}/files_#{@db_version}"
  end

  def version_path, do: @db_version

  def copy_data(src_db, dst_db, _opts \\ []) do
    dst_writable_size =
      dst_db
      |> CubDB.data_dir()
      |> Maintenance.path_writable_size()

    if dst_writable_size > 0 do
      if Maintenance.db_size(src_db) * 1.5 > dst_writable_size do
        fn -> reckless_copy(src_db, dst_db) end
      else
        fn ->
          cautious_copy(src_db, dst_db)
        end
      end
      |> then(&bulk_write(dst_db, &1))
    end
  end

  defp reckless_copy(src_db, dst_db) do
    src_db
    |> CubDB.select()
    |> Stream.each(fn {k, v} -> dst_db |> CubDB.put_new(k, v) end)
    |> Stream.run()
  end

  defp cautious_copy(src_db, dst_db) do
    src_db
    |> CubDB.select()
    # |> Stream.chunk_
    # |> Stream.reduce_while(fn entries ->
    #
    # end)
    |> Stream.each(fn {k, v} -> dst_db |> CubDB.put_new(k, v) end)
    |> Stream.run()
  end

  defp bulk_write(dst_db, action) do
    if dst_db == db() do
      ModeManager.start_bulk_write()
      action.()
      ModeManager.end_bulk_write()
    else
      Maintenance.sync_preparation(dst_db)
      action.()
      Maintenance.sync_finalization(dst_db)
    end
  end
end

defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  require Logger

  use GenServer

  import Chat.Db.Common

  alias Chat.Db.Maintenance
  alias Chat.Db.ModeManager
  alias Chat.Db.Pids
  alias Chat.Db.Queries
  alias Chat.Db.WritableUpdater

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

  def put(key, value),
    do: writable_action(fn -> budgeted_put(db(), key, value) end)

  def delete(key),
    do: writable_action(fn -> Queries.delete(db(), key) end)

  def bulk_delete({_min, _max} = range),
    do: writable_action(fn -> Queries.bulk_delete(db(), range) end)

  #
  # GenServer interface
  #

  def db do
    get_chat_db_env(:data_pid)
  end

  def file_db do
    get_chat_db_env(:file_pid)
  end

  def writable? do
    get_chat_db_env(:writable) != :no
  end

  def swap_pid(new_pids) do
    __MODULE__
    |> GenServer.call({:swap, new_pids})
  end

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, db} = CubDB.start_link(file_path(), auto_file_sync: true)
    {:ok, file_db} = CubDB.start_link(file_db_path(), auto_file_sync: false, auto_compact: false)

    put_chat_db_env(:data_pid, db)
    put_chat_db_env(:file_pid, file_db)

    WritableUpdater.check()
    "[db] Started database" |> Logger.notice()

    {:ok, {%Pids{main: db, file: file_db}, 100}}
  end

  @impl true
  def handle_call(
        {:swap, %Pids{main: new_data_db, file: new_file_db} = new},
        _from,
        {_, writable_size}
      ) do
    put_chat_db_env(:writable, :checking)
    old_data_pid = get_chat_db_env(:data_pid)
    old_file_pid = get_chat_db_env(:file_pid)

    put_chat_db_env(:data_pid, new_data_db)
    put_chat_db_env(:file_pid, new_file_db)
    WritableUpdater.check()
    "[db] pids swapped" |> Logger.info()

    old = %Pids{main: old_data_pid, file: old_file_pid}

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

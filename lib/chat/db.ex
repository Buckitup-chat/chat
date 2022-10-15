defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  require Logger

  use GenServer

  import Chat.Db.Common

  # alias Chat.Db.Maintenance
  alias Chat.Db.Pids
  alias Chat.Db.Queries
  alias Chat.Db.WritableUpdater
  alias Chat.FileFs

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

  def file_dir do
    get_chat_db_env(:files_base_dir)
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
    files_dir = file_db_path()

    put_chat_db_env(:data_pid, db)
    put_chat_db_env(:files_base_dir, files_dir)

    WritableUpdater.check()
    "[db] Started database" |> Logger.notice()

    {:ok, {%Pids{main: db, file: files_dir}, 100}}
  end

  @impl true
  def handle_call(
        {:swap, %Pids{main: new_data_db, file: new_file_dir} = new},
        _from,
        {_, writable_size}
      ) do
    put_chat_db_env(:writable, :checking)
    old_data_pid = get_chat_db_env(:data_pid)
    old_files_dir = get_chat_db_env(:files_base_dir)

    put_chat_db_env(:data_pid, new_data_db)
    put_chat_db_env(:files_base_dir, new_file_dir)
    WritableUpdater.check()
    "[db] pids swapped" |> Logger.info()

    old = %Pids{main: old_data_pid, file: old_files_dir}

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
    "#{@db_location}/files"
  end

  def version_path, do: @db_version

  def copy_data(src_db, dst_db, _opts \\ []) do
    # dst_writable_size = Maintenance.db_free_space(dst_db)

    # if dst_writable_size > 0 do
    #   if Maintenance.db_size(src_db) * 1.5 > dst_writable_size do
    reckless_copy(src_db, dst_db)
    #   else
    #     cautious_copy(src_db, dst_db, dst_writable_size)
    #   end
    # end
  end

  defp reckless_copy(src_db, dst_db) do
    src_db
    |> CubDB.select()
    |> Stream.each(fn {k, v} -> dst_db |> CubDB.put_new(k, v) end)
    |> Stream.run()
  end

  # defp cautious_copy(src_db, dst_db, initial_size) do
  #   src_db
  #   |> CubDB.select()
  #   |> Enum.reduce_while(initial_size, fn {k, v}, space_left ->
  #     item_size = calc_budget(k, v)

  #     disk_space =
  #       if item_size > space_left do
  #         Maintenance.db_free_space(dst_db) - 70_000_000
  #       else
  #         space_left
  #       end

  #     if disk_space > item_size do
  #       dst_db |> CubDB.put_new(k, v)
  #       {:cont, disk_space - item_size}
  #     else
  #       path = dst_db |> CubDB.data_dir()
  #       "[db] No space left while copying to #{path}" |> Logger.warn()
  #       {:halt, 0}
  #     end
  #   end)
  # end

  def copy_files(from, to) do
    "[db] files copy: #{from} => #{to}" |> Logger.info()
    batch_files_copy(from, to)
  end

  def batch_files_copy(from, to, size \\ 10) do
    from_keys = from |> FileFs.known_file_keys() |> MapSet.new()
    to_keys = to |> FileFs.known_file_keys() |> MapSet.new()

    from_length = from |> String.length()

    from_keys
    |> MapSet.difference(to_keys)
    |> MapSet.to_list()
    |> Enum.map(&FileFs.list_file_chunks(&1, from))
    |> List.flatten()
    |> Enum.chunk_every(size)
    |> Enum.each(fn chunk ->
      chunk
      |> Enum.each(fn from_file ->
        to_file = to <> String.slice(from_file, from_length..1500)
        to_dir = to_file |> String.slice(0, String.length(to_file) - 21)

        File.mkdir_p(to_dir)

        File.copy(from_file, to_file)
      end)

      Process.sleep(50)
    end)
  end
end

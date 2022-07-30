defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  use GenServer

  @db_version "v.6"
  @db_location Application.compile_env(:chat, :cub_db_file, "priv/db")

  @doc false
  def start_link(opts \\ %{}) do
    Chat.Time.init_time()
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    {:ok, db} = CubDB.start_link(file_path(), auto_file_sync: true)
    schedule_writable_check()

    {:ok, {db, path_writable?(file_path())}}
  end

  @doc false
  @impl true
  def handle_call(:db, _from, {pid, _} = state) do
    {:reply, pid, state}
  end

  def handle_call(:writable?, _from, {_, writable} = state) do
    {:reply, writable, state}
  end

  def handle_call({:swap, pid}, _from, {old_pid, writable?}) do
    {:reply, old_pid, {pid, writable?}}
  end

  @impl true
  def handle_info(:check_writable, {pid, _}) do
    schedule_writable_check()

    writable =
      if Process.alive?(pid) do
        pid
        |> CubDB.data_dir()
        |> path_writable?()
      else
        false
      end

    {:noreply, {pid, writable}}
  end

  def db do
    __MODULE__
    |> GenServer.call(:db)
  end

  def writable? do
    __MODULE__
    |> GenServer.call(:writable?)
  end

  def swap_pid(new_pid) do
    __MODULE__
    |> GenServer.call({:swap, new_pid})
  end

  def list(range, transform) do
    range
    |> list()
    |> Map.new(transform)
  end

  def list({min, max}) do
    db()
    |> CubDB.select(min_key: min, max_key: max)
  end

  def select({min, max}, amount) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Stream.take(amount)
  end

  def values({min, max}, amount) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Stream.take(amount)
    |> Stream.map(fn {_, v} -> v end)
  end

  def get_max_one(min, max) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Enum.take(1)
  end

  def get(key) do
    db()
    |> CubDB.get(key)
  end

  def put(key, value) do
    if writable?() do
      db()
      |> CubDB.put(key, value)
    end
  end

  def delete(key) do
    if writable?() do
      db()
      |> CubDB.delete(key)
    end
  end

  def bulk_delete({min, max}) do
    if writable?() do
      key_list =
        CubDB.select(db(),
          min_key: min,
          max_key: max
        )
        |> Enum.map(fn {key, _value} -> key end)

      CubDB.delete_multi(db(), key_list)
    end
  end

  def file_path do
    "#{@db_location}/#{@db_version}"
  end

  def version_path, do: @db_version

  def copy_data(src_db, dst_db, _opts \\ []) do
    if dst_db |> CubDB.data_dir() |> path_writable?() do
      sync_preparation(dst_db)

      if db_size(src_db) * 1.5 > db_free_space(dst_db) do
        reckless_copy(src_db, dst_db)
      else
        cautious_copy(src_db, dst_db)
      end

      if dst_db |> CubDB.data_dir() |> path_writable?() do
      end

      sync_finalization(dst_db)
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

  defp sync_preparation(db) do
    CubDB.set_auto_compact(db, false)
    CubDB.set_auto_file_sync(db, false)
  end

  defp sync_finalization(db) do
    CubDB.set_auto_file_sync(db, true)
    CubDB.set_auto_compact(db, true)
  end

  defp schedule_writable_check do
    Process.send_after(self(), :check_writable, 1000)
  end

  @free_space_buffer_100mb 100 * 1024 * 1024

  defp path_writable?(path) do
    path_free_space(path) > @free_space_buffer_100mb
  end

  defp path_free_space(path) do
    System.cmd("df", ["-P", path])
    |> elem(0)
    |> String.split("\n", trim: true)
    |> List.last()
    |> String.split(" ", trim: true)
    |> Enum.at(3)
    |> String.to_integer()
    |> Kernel.*(512)
  rescue
    _ -> 0
  end

  defp db_free_space(db) do
    db
    |> CubDB.data_dir()
    |> path_free_space()
  end

  defp db_size(db) do
    db
    |> CubDB.current_db_file()
    |> File.stat!()
    |> Map.get(:size)
  end
end

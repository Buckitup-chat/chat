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
    |> then(fn {:ok, list} -> list end)
  end

  def select({min, max}, amount) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true,
      pipe: [take: amount]
    )
    |> then(fn {:ok, list} -> list end)
  end

  def values({min, max}, amount) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true,
      pipe: [take: amount, map: fn {_, v} -> v end]
    )
    |> then(fn {:ok, list} -> list end)
  end

  def get_max_one(min, max) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true,
      pipe: [take: 1]
    )
    |> then(fn {:ok, list} -> list end)
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
      {:ok, key_list} =
        CubDB.select(db(),
          min_key: min,
          max_key: max,
          pipe: [
            map: fn {key, _value} -> key end
          ]
        )

      CubDB.delete_multi(db(), key_list)
    end
  end

  def file_path do
    "#{@db_location}/#{@db_version}"
  end

  def version_path, do: @db_version

  def copy_data(src_db, dst_db, opts \\ []) do
    target_amount = Keyword.get(opts, :target_amount, 1000)

    {:ok, entries} =
      if Keyword.has_key?(opts, :last_key) do
        src_db
        |> CubDB.select(
          min_key: opts[:last_key],
          min_key_inclusive: false,
          pipe: [take: target_amount]
        )
      else
        src_db |> CubDB.select(pipe: [take: target_amount])
      end

    last_key =
      entries
      |> Enum.map(fn {key, value} ->
        dst_db |> CubDB.put_new(key, value)
        key
      end)
      |> List.last()

    unless Enum.count(entries) < target_amount do
      copy_data(src_db, dst_db, last_key: last_key, target_amount: target_amount)
    end
  end

  defp path_writable?(path) do
    System.cmd("df", ["-P", path])
    |> elem(0)
    |> String.split("\n", trim: true)
    |> List.last()
    |> String.split(" ", trim: true)
    |> Enum.at(3)
    |> String.to_integer()
    |> then(&(&1 > 10))
  rescue
    _ -> false
  end
end

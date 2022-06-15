defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  use GenServer

  @db_version "v.4"
  @db_location Application.compile_env(:chat, :cub_db_file, "priv/db")

  @doc false
  def start_link(opts \\ %{}) do
    Chat.Time.init_time()
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    {:ok, _db} = CubDB.start_link(file_path(), auto_file_sync: true)
  end

  @doc false
  @impl true
  def handle_call(:db, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:swap, pid}, _from, old_pid) do
    {:reply, old_pid, pid}
  end

  def db do
    __MODULE__
    |> GenServer.call(:db)
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

  def get(key) do
    db()
    |> CubDB.get(key)
  end

  def put(key, value) do
    db()
    |> CubDB.put(key, value)
  end

  def delete(key) do
    db()
    |> CubDB.delete(key)
  end

  def bulk_delete({min, max}) do
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
end

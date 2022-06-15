defmodule Chat.AdminDb do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  use GenServer

  @db_location Application.compile_env(:chat, :admin_cub_db_file, "priv/admin_db")

  @doc false
  def start_link(opts) do
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

  def db do
    __MODULE__
    |> GenServer.call(:db)
  end

  def get(key) do
    db()
    |> CubDB.get(key)
  end

  def values(min, max) do
    db()
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      pipe: [map: fn {_, v} -> v end]
    )
    |> then(fn {:ok, list} -> list end)
  end

  def put(key, value) do
    db()
    |> CubDB.put(key, value)
  end

  def file_path do
    @db_location
  end
end

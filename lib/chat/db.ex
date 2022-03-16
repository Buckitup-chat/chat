defmodule Chat.Db do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  use GenServer

  @db_version "v.1"
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

  def db do
    __MODULE__
    |> GenServer.call(:db)
  end

  def list({min, max}, transform) do
    db()
    |> CubDB.select(min_key: min, max_key: max)
    |> then(fn {:ok, list} -> list end)
    |> Map.new(transform)
  end

  def get(key) do
    db()
    |> CubDB.get(key)
  end

  def put(key, value) do
    db()
    |> CubDB.put(key, value)
  end

  def file_path do
    "#{@db_location}/#{@db_version}"
  end
end

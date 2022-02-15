defmodule Chat.Images.Registry do
  @moduledoc "Images registry"

  use GenServer

  ### Interface

  def add(key, value), do: GenServer.call(__MODULE__, {:add, key, value})
  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  def all, do: GenServer.call(__MODULE__, :all)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  ### Implementation

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:all, _, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:add, key, value}, _, map) do
    map
    |> Map.put(key, value)
    |> then(&{:reply, :ok, &1})
  end

  @impl true
  def handle_call({:get, key}, _, map) do
    map
    |> Map.get(key)
    |> then(&{:reply, &1, map})
  end
end

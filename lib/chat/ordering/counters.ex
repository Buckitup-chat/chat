defmodule Chat.Ordering.Counters do
  @moduledoc "One time Key/Value message broker"

  use GenServer

  def set(key, value) do
    __MODULE__
    |> GenServer.call({:set, key, value})
  end

  def get(key) do
    __MODULE__
    |> GenServer.call({:get, key})
  end

  def next(key) do
    __MODULE__
    |> GenServer.call({:next, key})
  end

  ## Defining GenServer Callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:set, key, value}, _from, data) do
    {:reply, key, data |> Map.put(key, value)}
  end

  def handle_call({:get, key}, _from, data) do
    {:reply, data |> Map.get(key), data}
  end

  def handle_call({:next, key}, _from, data) do
    case Map.get(data, key) do
      nil -> {:reply, nil, data}
      old -> {:reply, old + 1, data |> Map.put(key, old + 1)}
    end
  end
end

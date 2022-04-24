defmodule Chat.Broker do
  @moduledoc "One time Key/Value message broker"

  use GenServer

  def store(value) do
    UUID.uuid4()
    |> tap(&GenServer.call(__MODULE__, {:put, &1, value}))
  end

  def get(key) do
    __MODULE__
    |> GenServer.call({:get, key})
  end

  ## Defining GenServer Callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(_) do
    Process.flag(:sensitive, true)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, data) do
    {:reply, key, data |> Map.put(key, value)}
  end

  @impl true
  def handle_call({:get, key}, _from, tokens) do
    {
      :reply,
      tokens |> Map.get(key),
      tokens |> Map.drop([key])
    }
  end
end

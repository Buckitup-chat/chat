defmodule Chat.ChunkedFilesBroker do
  @moduledoc "Keep secret while chunks are being uploaded"
  use GenServer

  alias Chat.Utils

  def generate(key) do
    secret = Utils.generate_binary_encrypt_key()

    GenServer.call(__MODULE__, {:put, key, secret})

    secret
  end

  def get(key) do
    __MODULE__
    |> GenServer.call({:get, key})
  end

  def forget(key) do
    __MODULE__
    |> GenServer.call({:forget, key})
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

  def handle_call({:get, key}, _from, tokens) do
    {
      :reply,
      tokens |> Map.get(key),
      tokens
    }
  end

  def handle_call({:forget, key}, _from, tokens) do
    {
      :reply,
      tokens |> Map.get(key),
      tokens |> Map.drop([key])
    }
  end
end

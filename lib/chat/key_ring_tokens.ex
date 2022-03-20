defmodule Chat.KeyRingTokens do
  @moduledoc "KeyRing Transfer Registry"

  use GenServer

  alias Chat.KeyRingTokens.Logic

  def create do
    Logic.generate_token_data()
    |> gen_call(:put)
    |> Logic.exporter_data()
  end

  def get(key, code) do
    key
    |> gen_call(:get)
    |> Logic.valid_importer_pid(code)
  end

  defp gen_call(data, msg) do
    GenServer.call(__MODULE__, {msg, data})
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
  def handle_call({:put, {key, value} = data}, _from, tokens) do
    {:reply, data, tokens |> Map.put(key, value)}
  end

  @impl true
  def handle_call({:get, key}, _from, tokens) do
    {
      :reply,
      tokens |> Map.get(key),
      tokens |> Map.drop([key])
    }
  end

  defmodule Logic do
    @moduledoc "Keyring export token logic"
    def generate_token_data(now \\ DateTime.utc_now() |> DateTime.to_unix()) do
      pid = self()
      <<code::integer>> = :crypto.strong_rand_bytes(1)

      {
        UUID.uuid4(),
        {pid, rem(code, 90) + 10, now}
      }
    end

    def exporter_data({key, {_, code, _}}), do: {key, code}

    def valid_importer_pid(value, exporter_code, now \\ DateTime.utc_now() |> DateTime.to_unix()) do
      with {pid, ^exporter_code, time} <- value,
           true <- time + 180 > now do
        {:ok, pid}
      else
        _ -> :error
      end
    end
  end
end

defmodule Chat.Challenge do
  @moduledoc "One time challenge broker for Proof-of-Possession"

  use GenServer

  import Tools.GenServerHelpers, only: [noreply: 1]

  @expiration_ms 60_000
  @cleanup_interval_ms 30_000

  def expiration_seconds do
    div(@expiration_ms, 1000)
  end

  def store do
    challenge = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    key = UUID.uuid4()
    GenServer.call(__MODULE__, {:put, key, challenge})

    {key, challenge}
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  ## Defining GenServer Callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, challenge}, _from, data) do
    expires_at = System.monotonic_time(:millisecond) + @expiration_ms
    {:reply, key, data |> Map.put(key, {challenge, expires_at})}
  end

  @impl true
  def handle_call({:get, key}, _from, data) do
    {value, rest} = Map.pop(data, key)

    result =
      with {challenge, expires_at} when is_integer(expires_at) <- value,
           true <- System.monotonic_time(:millisecond) < expires_at do
        challenge
      end

    {:reply, result, rest}
  end

  @impl true
  def handle_info(:cleanup, data) do
    now = System.monotonic_time(:millisecond)

    schedule_cleanup()

    data
    |> Enum.filter(fn {_, {_, expires_at}} -> expires_at > now end)
    |> Map.new()
    |> noreply()
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end

defmodule Chat.Pq.ReadSession do
  @moduledoc """
  Per-shape read sessions for trust-mode read gating.

  A session is `{token, user_hash, shape, expires_at}` in a public ETS table.
  Lookups read ETS directly (hot path on every shape poll); the GenServer only
  owns the table and sweeps expired entries.

  Fixed 5 min TTL from issue time. No refresh, no revoke. Not persisted.
  """

  use GenServer

  import Tools.GenServerHelpers, only: [noreply: 1]

  @table __MODULE__
  @ttl_ms 300_000
  @cleanup_interval_ms 60_000

  def ttl_seconds, do: div(@ttl_ms, 1000)

  def issue(user_hash, shape) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = now() + @ttl_ms
    true = :ets.insert(@table, {token, user_hash, shape, expires_at})

    token
  end

  def lookup(token) when is_binary(token) do
    now = now()

    case :ets.lookup(@table, token) do
      [{^token, user_hash, shape, expires_at}] when expires_at > now ->
        {:ok, %{user_hash: user_hash, shape: shape}}

      _ ->
        :error
    end
  end

  def lookup(_), do: :error

  ## GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, nil}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = now()
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_cleanup()

    noreply(state)
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval_ms)

  defp now, do: System.monotonic_time(:millisecond)
end

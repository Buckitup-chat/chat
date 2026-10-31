defmodule ChatWeb.RateLimiter do
  @moduledoc "ETS-based sliding window rate limiter."

  use GenServer

  @table __MODULE__
  @default_limit 10
  @default_window_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check(key, limit \\ @default_limit, window_ms \\ @default_window_ms) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    :ets.select_delete(@table, [{{key, :"$1"}, [{:<, :"$1", cutoff}], [true]}])

    count = :ets.select_count(@table, [{{key, :"$1"}, [{:>=, :"$1", cutoff}], [true]}])

    if count < limit do
      :ets.insert(@table, {key, now})
      :ok
    else
      oldest =
        case :ets.select(@table, [{{key, :"$1"}, [{:>=, :"$1", cutoff}], [:"$1"]}]) do
          [] -> now
          timestamps -> Enum.min(timestamps)
        end

      retry_after_s = max(div(oldest + window_ms - now, 1000), 1)
      {:error, retry_after_s}
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :duplicate_bag,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cutoff = System.monotonic_time(:millisecond) - @default_window_ms
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @default_window_ms)
end

defmodule Chat.Turn.RateLimiter do
  @moduledoc "Per-IP sliding-window rate limiter for TURN credential issuance"

  use GenServer

  alias Chat.Turn.Config

  @table __MODULE__
  @sweep_interval_ms :timer.minutes(5)

  def check_and_increment(ip) do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ref -> do_check(ip)
    end
  end

  defp do_check(ip) do
    now = System.os_time(:second)
    window_start = now - 3600
    limit = Config.rate_per_ip_hour()

    count =
      @table
      |> :ets.select_count([{{ip, :"$1"}, [{:>, :"$1", window_start}], [true]}])

    if count < limit do
      :ets.insert(@table, {ip, now})
      :ok
    else
      oldest_in_window =
        @table
        |> :ets.select([{{ip, :"$1"}, [{:>, :"$1", window_start}], [:"$1"]}])
        |> Enum.min()

      retry_after = oldest_in_window + 3600 - now
      {:error, max(retry_after, 1)}
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :duplicate_bag, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.os_time(:second) - 3600
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:"=<", :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end

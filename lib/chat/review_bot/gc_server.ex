defmodule Chat.ReviewBot.GcServer do
  @moduledoc "Schedules both soft-delete GC (hourly, per-bot) and hard-delete tombstone cleanup (daily)."

  use GenServer

  alias Chat.Data.OriginSetting
  alias Chat.Data.ReviewWriteToken
  alias Chat.ReviewBot.GarbageCollector
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @gc_interval :timer.hours(1)
  @clean_interval :timer.hours(24)
  @tombstone_grace_seconds div(:timer.hours(24 * 3 * 7), 1000)
  @seconds_per_day 86_400

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_gc()
    schedule_clean()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:gc_tick, state) do
    run_gc_for_all_bots()
    schedule_gc()
    {:noreply, state}
  end

  def handle_info(:clean, state) do
    threshold_ts = TimeKeeper.now_unix() - @tombstone_grace_seconds
    ReviewWriteToken.hard_delete_old_tombstones(threshold_ts)
    schedule_clean()
    {:noreply, state}
  end

  defp run_gc_for_all_bots do
    Chat.ReviewBot.Registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.each(fn bot_hash ->
      %{origin_hash: origin_hash} = Worker.info(bot_hash)
      ttl_days = OriginSetting.get_review_token_ttl_days(origin_hash)
      threshold_ts = TimeKeeper.now_unix() - ttl_days * @seconds_per_day

      origin_hash
      |> ReviewWriteToken.pending_expired_tokens(threshold_ts)
      |> GarbageCollector.soft_delete_tokens(bot_hash)
    end)
  end

  defp schedule_gc, do: Process.send_after(self(), :gc_tick, @gc_interval)
  defp schedule_clean, do: Process.send_after(self(), :clean, @clean_interval)
end

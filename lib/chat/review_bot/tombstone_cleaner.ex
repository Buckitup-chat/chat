defmodule Chat.ReviewBot.TombstoneCleaner do
  @moduledoc "Periodically hard-deletes soft-deleted review write tokens past the grace period."

  use GenServer

  alias Chat.Data.ReviewWriteToken
  alias Chat.TimeKeeper

  @interval :timer.hours(24)
  @grace_period_seconds 3 * 7 * 86_400

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:clean, state) do
    threshold_ts = TimeKeeper.now_unix() - @grace_period_seconds
    ReviewWriteToken.hard_delete_old_tombstones(threshold_ts)
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :clean, @interval)
end

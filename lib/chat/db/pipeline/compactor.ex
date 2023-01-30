defmodule Chat.Db.Pipeline.Compactor do
  @moduledoc """
  Awaits no activity to start compaction.
  If activity comes when compaction is sterted - cancels it
  """
  use GenServer

  import Tools.GenServerHelpers

  alias Chat.Db.Maintenance

  @no_activity_timeout_m 7

  def activity(proc), do: proc |> GenServer.cast(:activity)

  #
  #   Implementation
  #

  def start_link(opts) do
    name = opts |> Keyword.fetch!(:name)

    GenServer.start_link(__MODULE__, opts |> Keyword.drop([:name]), name: name)
  end

  @impl true
  def init(opts) do
    {
      false,
      opts |> Keyword.fetch!(:db),
      schedule_timer()
    }
    |> ok()
  end

  @impl true
  def handle_cast(:activity, {started?, db, timer}) do
    cancel_timer(timer)

    if started? do
      stop_compaction(db)
    end

    {false, db, schedule_timer()}
    |> noreply()
  end

  @impl true
  def handle_info(:start, {started?, db, timer}) do
    if not started? and there_is_free_space?(db) do
      start_compaction(db)

      {true, db, timer} |> noreply()
    else
      {false, db, timer}
      |> noreply()
    end
  end

  defp there_is_free_space?(db) do
    Maintenance.db_free_space(db) > Maintenance.db_size(db)
  end

  defp schedule_timer do
    Process.send_after(self(), :start, :timer.minutes(@no_activity_timeout_m))
  end

  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp start_compaction(db), do: CubDB.compact(db)
  defp stop_compaction(db), do: CubDB.halt_compaction(db)
end

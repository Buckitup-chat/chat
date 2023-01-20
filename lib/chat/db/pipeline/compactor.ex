defmodule Chat.Db.Pipeline.Compactor do
  @moduledoc """
  Awaits no activity to start compaction.
  If activity comes when compaction is sterted - cancels it
  """

  use GenServer

  import Tools.GenServerHelpers

  @no_activity_timeout_m 7

  def activity, do: __MODULE__ |> GenServer.cast(:activity)

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
      opts |> Keyword.fetch!(:db_name),
      schedule_timer()
    }
    |> ok()
  end

  @impl true
  def handle_cast(:activity, {started?, db, timer}) do
    Process.cancel_timer(timer)

    if started? do
      stop_compaction(db)
    end

    {false, db, schedule_timer()}
    |> noreply()
  end

  @impl true
  def handle_info(:start, {started?, db, timer} = state) do
    if not started? and there_is_free_space?(db) do
      CubDB.compact(db)

      {true, db, timer} |> noreply()
    else
      state |> noreply()
    end
  end

  defp there_is_free_space?(_db), do: false

  defp schedule_timer do
    Process.send_after(self(), :start, :timer.minutes(@no_activity_timeout_m))
  end

  defp stop_compaction(db) do
    CubDB.halt_compaction(db)
  end
end

defmodule Chat.Db.ChangeTracker.Logger do
  @moduledoc """
  Genserver to log long awaiting keys every minute
  """
  alias Chat.Db.ChangeTracker
  import Tools.GenServerHelpers

  use GenServer

  require Logger

  @check_delay :timer.minutes(1)

  # Implementation

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_timer(@check_delay)
    |> ok()
  end

  @impl true
  def handle_info(:check, _) do
    {n, top_keys} = ChangeTracker.long_expiry_stats()

    if n > 0 do
      [
        "[ChangeTracker stats] ",
        n,
        " awaiting keys, for instance: ",
        inspect(top_keys, pretty: true)
      ]
      |> Logger.warn()
    end

    schedule_timer(@check_delay)
    |> noreply()
  end

  defp schedule_timer(time) do
    Process.send_after(self(), :check, time)
  end
end

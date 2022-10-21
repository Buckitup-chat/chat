defmodule Chat.Db.DbSyncWatcher do
  @moduledoc "File Sync to CubDB"

  use GenServer

  @interval :timer.seconds(5)

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval = :timer.send_interval(@interval, :tick)
    {:ok, interval}
  end

  @impl true
  def handle_info(:tick, state) do
    Chat.Db.db() |> CubDB.file_sync()

    {:noreply, state}
  end
end

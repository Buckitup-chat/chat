defmodule Chat.Db.ModeManager do
  @moduledoc "Switches DB write mode and compaction"

  use GenServer

  require Logger

  alias Chat.Db
  alias Chat.Db.Maintenance

  def start_bulk_write do
    #    __MODULE__
    #    |> GenServer.call(:start)
  end

  def end_bulk_write do
    #    __MODULE__
    #    |> GenServer.cast(:end)
  end

  #
  # GenServer implementation
  #

  @doc false
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    {:ok, 0}
  end

  @impl true
  def handle_call(:start, _, n) do
    Logger.warn("mode start #{n}")

    if n == 0 do
      Db.db() |> Maintenance.sync_preparation()
    end

    {:reply, :ok, n + 1}
  end

  @impl true
  def handle_cast(:end, n) do
    Logger.warn("mode end #{n}")

    if n == 1 do
      Db.db() |> Maintenance.sync_finalization()
    end

    {:noreply, max(0, n - 1)}
  end
end

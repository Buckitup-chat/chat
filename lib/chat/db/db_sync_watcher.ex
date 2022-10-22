defmodule Chat.Db.DbSyncWatcher do
  @moduledoc "File Sync to CubDB"

  use GenServer

  defstruct [:cool_down_timer, :count]

  @timeout :timer.seconds(5)
  @amount 100

  def mark do
    __MODULE__
    |> GenServer.cast(:mark)
  end

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, clean_state()}
  end

  @impl true
  def handle_cast(:mark, %{count: count, cool_down_timer: timer} = state) do
    if timer do
      Process.cancel_timer(timer)
    end

    if count > @amount do
      sync()

      clean_state()
      |> noreply()
    end

    %{state | count: count + 1, cool_down_timer: Process.send_after(self(), :sync, @timeout)}
    |> noreply()
  end

  @impl true
  def handle_info(:sync, _) do
    sync()

    clean_state()
    |> noreply()
  end

  defp sync, do: Chat.Db.db() |> CubDB.file_sync()

  defp clean_state, do: %__MODULE__{count: 0}

  defp noreply(x), do: {:noreply, x}
end

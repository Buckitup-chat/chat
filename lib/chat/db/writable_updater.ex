defmodule Chat.Db.WritableUpdater do
  @moduledoc "Checks and updated writable status of DB"

  use GenServer

  alias Chat.Db
  alias Chat.Db.Maintenance

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send_db_current_writable_size()
    schedule_writable_check()

    {:ok, nil}
  end

  @impl true
  def handle_info(:check_writable, state) do
    send_db_current_writable_size()
    schedule_writable_check()

    {:noreply, state}
  end

  #
  # Logic
  #

  defp schedule_writable_check do
    Process.send_after(self(), :check_writable, 1000)
  end

  defp send_db_current_writable_size do
    pid = Db.db()

    if Process.alive?(pid) do
      pid
      |> CubDB.data_dir()
      |> Maintenance.path_writable_size()
    else
      0
    end
    |> then(fn size ->
      Db
      |> Process.whereis()
      |> send({:writable_size, size})
    end)
  end
end

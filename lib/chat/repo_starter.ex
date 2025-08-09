defmodule Chat.RepoStarter do
  @moduledoc """
  Module responsible for starting Chat.Repo with automatic retries.
  """
  use GenServer
  require Logger

  @retry_interval :timer.seconds(3)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args) do
    opts =
      case Application.get_env(:chat, :env) do
        :test -> Keyword.get(args, :opts, [])
        _ -> [name: __MODULE__]
      end

    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  @spec init(keyword()) :: {:ok, map()}
  def init(args) do
    supervisor = Keyword.get(args, :supervisor, Chat.RepoDynamicSupervisor)

    Process.send_after(self(), :start_repo, @retry_interval)

    {:ok, %{supervisor: supervisor}}
  end

  @impl GenServer
  @spec handle_info(:start_repo, map()) :: {:noreply, map()}
  def handle_info(:start_repo, state) do
    {:ok, _pid} = DynamicSupervisor.start_child(state.supervisor, Chat.Repo)
    run_migrations()
    {:ok, _pid} = DynamicSupervisor.start_child(state.supervisor, Chat.User.UsersBroker)
    # {:ok, _pid} = DynamicSupervisor.start_child(state.supervisor, Chat.Rooms.RoomsBroker)
    {:noreply, state}
  end

  @doc """
  Runs Ecto migrations for the application.
  """
  @spec run_migrations() :: [any()]
  def run_migrations do
    Logger.info("Running database migrations")
    path = Application.app_dir(:chat, "priv/repo/migrations")

    Ecto.Migrator.run(Chat.Repo, path, :up, all: true)
    |> tap(fn
      [] -> Logger.info("No migrations to run, database is up to date")
      migrations -> Logger.info("Successfully ran #{length(migrations)} migrations")
    end)
  rescue
    e ->
      Logger.error("Migration failed with error: #{inspect(e)}")
      []
  end
end

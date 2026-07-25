defmodule Chat.Db.Boot.RepoReady do
  @moduledoc "Stage: start Chat.Repo, run migrations."

  use GracefulGenServer
  use Toolbox.OriginLog

  alias Toolbox.StagedSupervisor

  @impl true
  def on_init(opts) do
    supervisor = Keyword.get(opts, :supervisor, Chat.RepoDynamicSupervisor)
    next = Keyword.get(opts, :next)

    %{supervisor: supervisor, next: next}
    |> tap(fn _ -> send(self(), :start) end)
  end

  @impl GracefulGenServer
  def on_msg(:start, %{supervisor: supervisor} = state) do
    start_repos(supervisor)
    run_migrations()
    send(self(), :done)
    {:noreply, state}
  end

  def on_msg(:done, %{next: next} = state) do
    if next, do: StagedSupervisor.start_next_stage(next[:under], next[:run])
    {:noreply, state}
  end

  @impl true
  def on_exit(_reason, _state), do: :ok

  defp start_repos(supervisor) do
    {:ok, _pid} = DynamicSupervisor.start_child(supervisor, Chat.Repo)
  end

  def run_migrations(repo \\ Chat.Repo) do
    log("Running database migrations on #{repo}", :info)
    path = Application.app_dir(:chat, "priv/repo/migrations")

    Ecto.Migrator.run(repo, path, :up, all: true)
    |> tap(fn
      [] -> log("No migrations to run, database is up to date", :info)
      migrations -> log("Successfully ran #{length(migrations)} migrations on #{repo}", :info)
    end)
  rescue
    e ->
      log("Migration on #{repo} failed with error: #{inspect(e)}", :error)
      []
  end
end

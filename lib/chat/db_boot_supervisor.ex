defmodule Chat.DbBootSupervisor do
  @moduledoc """
  Staged supervisor for database boot sequence on host.

  Stages: Repo → Electric check → ChunkPipeline.
  On device, Platform.App.DatabaseSupervisor handles this instead.
  """

  use Supervisor

  import Toolbox.StagedSupervisor

  alias Chat.Db.Boot.ElectricReady
  alias Chat.Db.Boot.RepoReady

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  if Application.compile_env(:chat, :env) == :test do
    @impl true
    def init(_init_arg) do
      sup = Chat.RepoDynamicSupervisor
      {:ok, _} = DynamicSupervisor.start_child(sup, {Chat.Repo, [name: Chat.Repo]})
      RepoReady.run_migrations()

      {:ok, _} =
        DynamicSupervisor.start_child(
          sup,
          {Chat.Data.File.ChunkPipelineSupervisor, drive_id: :internal, repo: Chat.Repo}
        )

      Supervisor.init([], strategy: :one_for_one)
    end
  else
    @impl true
    def init(_init_arg) do
      task_supervisor = __MODULE__.TaskSupervisor

      [
        use_task(task_supervisor),
        {:step, RepoStarted,
         {RepoReady, task_in: task_supervisor}
         |> exit_takes(30_000)},
        {:step, ElectricVerified,
         {ElectricReady, task_in: task_supervisor}
         |> exit_takes(15_000)},
        {Chat.Data.File.ChunkPipelineSupervisor, drive_id: :internal, repo: Chat.Repo}
      ]
      |> prepare_stages(Chat.Db.BootStages)
      |> Supervisor.init(strategy: :rest_for_one, max_restarts: 10, max_seconds: 30)
    end
  end
end

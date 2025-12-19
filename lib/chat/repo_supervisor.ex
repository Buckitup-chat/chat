defmodule Chat.RepoSupervisor do
  @moduledoc """
  Supervisor for the Chat.Repo and its starter.

  This supervisor manages:
  1. A DynamicSupervisor where the Repo will be started
  2. A RepoStarter that will retry starting the Repo when it fails
  """
  use Supervisor

  @doc """
  Starts the RepoSupervisor process.
  """
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # DynamicSupervisor for the Repo
      {DynamicSupervisor, name: Chat.RepoDynamicSupervisor, strategy: :one_for_one},
      # RepoStarter that will attempt to start the Repo and retry if it fails
      Chat.RepoStarter
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule Chat.ReviewBot.Supervisor do
  @moduledoc "Supervises the review bot registry and dynamic worker supervisor."

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Chat.ReviewBot.Registry},
      {DynamicSupervisor, name: Chat.ReviewBot.WorkerSupervisor, strategy: :one_for_one},
      Chat.ReviewBot.GcServer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

defmodule Chat.Db.InternalDbSupervisor do
  @moduledoc """
  Supervisor for internal DB
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Chat.Db.InternalDb
    |> Chat.Db.supervise(Chat.Db.file_path())
    |> Supervisor.init(strategy: :rest_for_one, max_restarts: 1, max_seconds: 5)
  end
end

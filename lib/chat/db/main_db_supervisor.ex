defmodule Chat.Db.MainDbSupervisor do
  @moduledoc """
  Supervisor for main DB
  """

  use Supervisor

  def start_link(path) do
    Supervisor.start_link(__MODULE__, path, name: __MODULE__)
  end

  @impl true
  def init(path) do
    Chat.Db.MainDb
    |> Chat.Db.supervise(path)
    |> Supervisor.init(strategy: :rest_for_one)
  end
end

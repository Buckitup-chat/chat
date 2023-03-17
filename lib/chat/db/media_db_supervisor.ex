defmodule Chat.Db.MediaDbSupervisor do
  @moduledoc """
  Supervisor for media DB
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init([db, path]) do
    db
    |> Chat.Db.supervise(path)
    |> Supervisor.init(strategy: :rest_for_one)
  end
end

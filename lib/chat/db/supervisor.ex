defmodule Chat.Db.Supervisor do
  @moduledoc "DB processes supervisor"
  use Supervisor

  require Logger

  alias Chat.Db.Switching

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # DB changes tracking
      {Task.Supervisor, name: Chat.Db.ChangeTracker.Tasks},
      Chat.Db.ChangeTracker,
      # DB part
      Chat.Db.InternalDbSupervisor,
      {Task,
       fn ->
         Chat.Db.InternalDb |> Switching.set_default()

         ["[db] ", "Started database"] |> Logger.notice()
       end},
      # DB status broadcaster
      Chat.Db.StatusPoller,
      # Free spaces broadcaster
      Chat.Db.FreeSpacesPoller
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

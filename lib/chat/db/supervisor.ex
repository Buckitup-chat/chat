defmodule Chat.Db.Supervisor do
  @moduledoc "DB processes supervisor"
  use Supervisor

  alias Chat.Db
  alias Chat.Db.DbSyncWatcher
  alias Chat.Db.FileFsProxy
  alias Chat.Db.StatusPoller
  alias Chat.Db.WritableUpdater

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      FileFsProxy,
      WritableUpdater,
      Db,
      StatusPoller,
      DbSyncWatcher
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

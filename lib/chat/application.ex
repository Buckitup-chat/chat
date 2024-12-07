defmodule Chat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Chat.AdminDb.AdminLogger

  @impl true
  def start(_type, _args) do
    Logger.put_application_level(:ssl, :error)
    log_version()

    children = [
      # Start the Telemetry supervisor
      ChatWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Chat.PubSub},
      # Start DB
      Chat.Ordering.Counters,
      Chat.Db.Supervisor,
      Chat.AdminDb,
      # Application Services
      Chat.KeyRingTokens,
      Chat.Broker,
      Chat.ChunkedFilesBroker,
      Chat.User.UsersBroker,
      Chat.Rooms.RoomsBroker,
      Chat.RoomMessageLinksBroker,
      Chat.Sync.CargoRoom,
      Chat.Sync.OnlinersSync,
      Chat.Sync.UsbDriveDumpRoom,
      {DynamicSupervisor, name: Chat.Upload.UploadSupervisor},
      {DynamicSupervisor, name: Chat.Db.FreeSpacesSupervisor},
      ChatWeb.Presence,
      # Start the Endpoint (http/https)
      ChatWeb.Endpoint,
      Chat.NetworkSynchronization.Supervisor,
      # Supervised tasks caller
      {Task.Supervisor, name: Chat.TaskSupervisor},
      {Task,
       fn ->
         {:ok, _pid} = AdminLogger |> Logger.add_backend()

         Task.Supervisor.start_child(
           Chat.TaskSupervisor,
           fn ->
             log_version()
             Process.sleep(:timer.minutes(5))

             AdminLogger.get_current_generation()
             |> AdminLogger.remove_old_generations()
           end,
           shutdown: :brutal_kill
         )

         Task.Supervisor.start_child(
           Chat.TaskSupervisor,
           fn ->
             Chat.NetworkSynchronization.Retrieval.load_all_chat_modules()
             Chat.NetworkSynchronization.init_workers()
           end,
           shutdown: :brutal_kill
         )
       end}
      # Start a worker by calling: Chat.Worker.start_link(arg)
      # {Chat.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chat.Supervisor]

    Supervisor.start_link(children ++ more_children(), opts)
  end

  # coveralls-ignore-start
  if Application.compile_env(:chat, :env) == :test do
    defp more_children, do: []
  else
    defp more_children, do: [Chat.Upload.StaleUploadsPruner]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # coveralls-ignore-end

  defp log_version do
    ver = System.get_env("RELEASE_SYS_CONFIG")

    if ver do
      ver
      |> String.split("/", trim: true)
      |> Enum.at(3)
      |> then(&Logger.info(["[chat] ", &1]))
    end
  end
end

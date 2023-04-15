defmodule Chat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @env Application.compile_env(:chat, :env)

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
      Chat.UsersBroker,
      Chat.RoomsBroker,
      Chat.RoomMessageLinksBroker,
      Chat.Sync.CargoRoom,
      Chat.Sync.OnlinersSync,
      {DynamicSupervisor, name: Chat.Upload.UploadSupervisor},
      ChatWeb.Presence,
      # Start the Endpoint (http/https)
      ChatWeb.Endpoint,
      # Supervised tasks caller
      {Task.Supervisor, name: Chat.TaskSupervisor}
      # Start a worker by calling: Chat.Worker.start_link(arg)
      # {Chat.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chat.Supervisor]

    Supervisor.start_link(children ++ more_children(@env), opts)
  end

  defp more_children(:test), do: []
  # coveralls-ignore-start
  defp more_children(_env), do: [Chat.Upload.StaleUploadsPruner]

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

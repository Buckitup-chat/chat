defmodule Chat.Turn.Supervisor do
  @moduledoc "Starts TURN relay listeners when TURN is enabled"

  use Supervisor

  require Logger

  alias Chat.Turn.Auth
  alias Chat.Turn.Config

  @turn_port 3478
  @relay_min_port 49_152
  @relay_max_port 65_535
  @max_allocations 4
  @max_permissions 16

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      if Config.enabled?() do
        [{Task, fn -> start_listeners() end}]
      else
        Logger.info("[turn] TURN relay disabled — no public IP")
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp start_listeners do
    ip = {0, 0, 0, 0}
    opts = listener_opts()

    case :stun_listener.add_listener(ip, @turn_port, :udp, opts) do
      :ok -> Logger.info("[turn] UDP listener started on 0.0.0.0:#{@turn_port}")
      {:error, reason} -> Logger.error("[turn] UDP listener failed: #{inspect(reason)}")
    end

    case :stun_listener.add_listener(ip, @turn_port, :tcp, opts) do
      :ok -> Logger.info("[turn] TCP listener started on 0.0.0.0:#{@turn_port}")
      {:error, reason} -> Logger.error("[turn] TCP listener failed: #{inspect(reason)}")
    end
  end

  defp listener_opts do
    [
      use_turn: true,
      auth_type: :user,
      auth_realm: Config.realm(),
      auth_fun: &Auth.auth_fun/2,
      turn_ipv4_address: Config.public_ip_tuple(),
      turn_min_port: @relay_min_port,
      turn_max_port: @relay_max_port,
      turn_max_allocations: @max_allocations,
      turn_max_permissions: @max_permissions
    ]
  end
end

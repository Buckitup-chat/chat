defmodule Chat.Turn.Supervisor do
  @moduledoc "Starts the public TURN relay listeners (host only) when TURN is enabled"

  use Supervisor

  use Toolbox.OriginLog

  alias Chat.Turn.Config
  alias Chat.Turn.Listener

  @any_ip {0, 0, 0, 0}

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      if Config.enabled?() do
        [{Task, fn -> start_listeners() end}]
      else
        log("TURN relay disabled — no public IP", :info)
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp start_listeners do
    public_ip = Config.public_ip_tuple()
    opts = Listener.opts(public_ip, [public_ip])

    Enum.each([:udp, :tcp], fn transport ->
      case Listener.add(@any_ip, transport, opts) do
        :ok -> log("#{transport} listener started on 0.0.0.0:#{Listener.port()}", :info)
        {:error, reason} -> log("#{transport} listener failed: #{inspect(reason)}", :error)
      end
    end)
  end
end

defmodule Chat.NetworkSynchronization.Supervisor do
  @moduledoc "Supervises workers for each source started"

  use Supervisor

  alias Chat.NetworkSynchronization.PeerDetection.LanDetector
  alias Chat.NetworkSynchronization.Store

  def start_link(arg) do
    name = Keyword.get(arg, :name, __MODULE__)

    opts =
      arg
      |> Keyword.drop([:name])
      |> Keyword.put(:supervisor_name, name)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    supervisor_name = Keyword.fetch!(opts, :supervisor_name)
    dynamic_name = Keyword.get(opts, :dynamic_name, Module.concat(supervisor_name, Dynamic))
    registry_name = Keyword.get(opts, :registry_name, Module.concat(supervisor_name, Registry))
    detector_name = Keyword.get(opts, :detector_name, Module.concat(supervisor_name, Detector))

    children = [
      {DynamicSupervisor, name: dynamic_name, strategy: :one_for_one},
      {Registry, name: registry_name, keys: :unique},
      {LanDetector, name: detector_name}
    ]

    Store.init()

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

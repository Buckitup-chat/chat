defmodule Chat.NetworkSynchronization.Electric.PeerSync do
  @moduledoc """
  Supervisor that manages all shape consumers for a single Electric peer.

  Started once per discovered peer. Starts one `ShapeConsumer` per shape
  (`user_card`, `user_storage`) and supervises them independently.

  Fetches the PostgreSQL system_identifier from the peer for reliable
  identification across DHCP network changes.
  """

  use Supervisor

  require Logger

  alias Chat.NetworkSynchronization.Electric.PeerIdentifier
  alias Chat.NetworkSynchronization.Electric.ShapeConsumer
  alias Chat.NetworkSynchronization.Electric.Shapes

  def start_link(opts) do
    peer_url = Keyword.fetch!(opts, :peer_url)
    Supervisor.start_link(__MODULE__, peer_url, Keyword.drop(opts, [:peer_url]))
  end

  @impl true
  def init(peer_url) do
    case PeerIdentifier.fetch_system_identifier(peer_url) do
      {:ok, system_identifier} ->
        children =
          Enum.map(Shapes.all(), fn shape ->
            Supervisor.child_spec(
              {ShapeConsumer,
               peer_url: peer_url, system_identifier: system_identifier, shape: shape},
              id: {ShapeConsumer, shape}
            )
          end)

        Supervisor.init(children, strategy: :one_for_one)

      {:error, reason} ->
        Logger.error(
          "Failed to initialize PeerSync for #{peer_url}: could not fetch system_identifier (#{inspect(reason)})"
        )

        {:stop, {:shutdown, :no_system_identifier}}
    end
  end
end

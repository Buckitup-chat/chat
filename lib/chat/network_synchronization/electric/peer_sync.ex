defmodule Chat.NetworkSynchronization.Electric.PeerSync do
  @moduledoc """
  Supervisor that manages all shape consumers for a single Electric peer.

  Started once per discovered peer, once `PeerConnector` has already resolved
  the peer's PostgreSQL `system_identifier`. Starts one `ShapeConsumer` per
  shape (`user_card`, `user_storage`) and supervises them independently.

  `init/1` takes the resolved identifier as an argument (instead of fetching
  it itself) so it never fails: a transient lookup failure is `PeerConnector`'s
  problem to retry, not a reason to trip this supervisor's restart intensity.
  """

  use Supervisor

  alias Chat.Data.Shapes
  alias Chat.NetworkSynchronization.Electric.ShapeConsumer

  def start_link(opts) do
    peer_url = Keyword.fetch!(opts, :peer_url)
    system_identifier = Keyword.fetch!(opts, :system_identifier)

    Supervisor.start_link(
      __MODULE__,
      {peer_url, system_identifier},
      Keyword.drop(opts, [:peer_url, :system_identifier])
    )
  end

  @impl true
  def init({peer_url, system_identifier}) do
    Shapes.sync_shape_names()
    |> Enum.map(fn shape ->
      Supervisor.child_spec(
        {ShapeConsumer, peer_url: peer_url, system_identifier: system_identifier, shape: shape},
        id: {ShapeConsumer, shape}
      )
    end)
    |> Supervisor.init(strategy: :one_for_one)
  end
end

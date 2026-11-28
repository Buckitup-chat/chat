defmodule Chat.NetworkSynchronization.Electric.PeerSyncTest.ConsumerStub do
  @moduledoc false
  use Agent

  def start_link(opts), do: Agent.start_link(fn -> opts end)
end

defmodule Chat.NetworkSynchronization.Electric.PeerSyncTest do
  use ExUnit.Case, async: true

  import Support.Rewire

  alias Chat.Data.Shapes
  alias Chat.NetworkSynchronization.Electric.PeerSync
  alias Chat.NetworkSynchronization.Electric.PeerSyncTest.ConsumerStub

  rewire(PeerSync,
    ShapeConsumer: Chat.NetworkSynchronization.Electric.PeerSyncTest.ConsumerStub
  )

  test "starts one consumer per sync shape for the peer" do
    sup =
      start_supervised!({PeerSync, peer_url: "http://10.0.0.7:4444", system_identifier: "sys-7"})

    children = Supervisor.which_children(sup)

    assert children |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
             Shapes.sync_shape_names() |> Enum.map(&{ConsumerStub, &1}) |> Enum.sort()

    {{ConsumerStub, shape}, pid, :worker, _} = hd(children)

    assert Agent.get(pid, & &1) == [
             peer_url: "http://10.0.0.7:4444",
             system_identifier: "sys-7",
             shape: shape
           ]
  end
end

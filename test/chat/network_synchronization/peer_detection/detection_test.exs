defmodule ChatTest.NetworkSynchronization.PeerDetection.DetectionTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization.PeerDetection.LanDetection
  alias ChatSupport.Mocks.NetworkSynchronization.NeuronMockForLanDetection
  alias ChatSupport.Mocks.NetworkSynchronization.SynchronizationMockForLanDetection

  rewire(LanDetection, [
    {Chat.NetworkSynchronization, SynchronizationMockForLanDetection},
    {Neuron, NeuronMockForLanDetection}
  ])

  test "lan_detection" do
    %{
      ip: "10.10.10.10",
      mask: "255.255.255.0",
      known_peers: ["10.10.10.11", "10.10.10.120", "10.10.10.253", "some.domain.host"],
      new_peers: NeuronMockForLanDetection.new_peers_list()
    }
    |> set_known_peers
    |> assert_known_peers_in_place
    |> run_lan_detection
    |> assert_correct_peers_added
  end

  defp set_known_peers(context) do
    context.known_peers
    |> SynchronizationMockForLanDetection.set_known()

    context
  end

  defp run_lan_detection(context) do
    LanDetection.on_lan(context.ip, context.mask)
    context
  end

  defp assert_correct_peers_added(context) do
    current_peers =
      SynchronizationMockForLanDetection.synchronisation()
      |> Enum.map(fn {%{url: url}, _} -> URI.parse(url) |> Map.get(:host) end)

    context.new_peers
    |> Enum.all?(fn host -> Enum.member?(current_peers, host) end)
    |> tap(fn in_place? ->
      assert in_place?
    end)

    context
  end

  defp assert_known_peers_in_place(context) do
    SynchronizationMockForLanDetection.synchronisation()
    |> Enum.map(fn {%{url: url}, _} -> URI.parse(url) |> Map.get(:host) end)
    |> Enum.all?(fn host -> Enum.member?(context.known_peers, host) end)
    |> tap(fn in_place? ->
      assert in_place?
    end)

    context
  end
end

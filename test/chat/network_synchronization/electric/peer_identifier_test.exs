defmodule Chat.NetworkSynchronization.Electric.PeerIdentifierTest do
  use ExUnit.Case, async: true

  alias Chat.NetworkSynchronization.Electric.PeerIdentifier

  describe "fetch_system_identifier/1" do
    test "returns error for invalid peer_url" do
      assert {:error, :invalid_peer_url} = PeerIdentifier.fetch_system_identifier("invalid")
    end

    test "returns error for unreachable peer" do
      assert {:error, _reason} =
               PeerIdentifier.fetch_system_identifier("http://192.0.2.1:6000")
    end
  end

  describe "build_postgres_url/1" do
    test "returns error for unreachable peer" do
      peer_url = "http://192.168.1.100:6000"
      assert {:error, _reason} = PeerIdentifier.query_system_identifier(peer_url)
    end
  end
end

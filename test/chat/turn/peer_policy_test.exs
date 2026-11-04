defmodule Chat.Turn.PeerPolicyTest do
  use ExUnit.Case, async: true

  alias Chat.Turn.Cidr
  alias Chat.Turn.PeerPolicy

  @public_ip {203, 0, 113, 1}
  @wlan_ip {192, 168, 25, 1}
  @eth_ip {192, 168, 24, 1}
  @wlan_pool Cidr.pool({192, 168, 25, 10}, {192, 168, 25, 250})
  @eth_pool Cidr.pool({192, 168, 24, 10}, {192, 168, 24, 250})

  describe "server relay" do
    test "public peer is granted" do
      assert server_opts() |> PeerPolicy.allowed?({8, 8, 8, 8})
    end

    test "private, loopback and own public address are refused" do
      opts = server_opts()

      refute PeerPolicy.allowed?(opts, {192, 168, 1, 10})
      refute PeerPolicy.allowed?(opts, {127, 0, 0, 1})
      refute PeerPolicy.allowed?(opts, @public_ip)
    end

    test "every base range stays blacklisted" do
      opts = server_opts()

      for {net, _} <- PeerPolicy.base_blacklist() do
        refute PeerPolicy.allowed?(opts, net), "#{inspect(net)} should be refused"
      end
    end
  end

  describe "device relay with LAN pools as blacklist holes" do
    test "pool addresses on wlan0 and eth0 are granted" do
      opts = device_opts()

      assert PeerPolicy.allowed?(opts, {192, 168, 25, 20})
      assert PeerPolicy.allowed?(opts, {192, 168, 24, 20})
    end

    test "loopback and device addresses are refused" do
      opts = device_opts()

      refute PeerPolicy.allowed?(opts, {127, 0, 0, 1})
      refute PeerPolicy.allowed?(opts, @wlan_ip)
      refute PeerPolicy.allowed?(opts, @eth_ip)
    end

    test "other private ranges stay refused" do
      opts = device_opts()

      refute PeerPolicy.allowed?(opts, {192, 168, 26, 20})
      refute PeerPolicy.allowed?(opts, {10, 1, 0, 5})
    end

    test "whitelist is always empty so stun checks peers one by one" do
      assert Keyword.fetch!(device_opts(), :turn_whitelist_peers) == []
    end
  end

  describe "eth0 internet lease" do
    test "lease network is granted except the lease itself" do
      lease = {10, 1, 2, 3}
      opts = PeerPolicy.listener_opts([lease], [Cidr.network(lease, 16)])

      assert PeerPolicy.allowed?(opts, {10, 1, 0, 5})
      assert PeerPolicy.allowed?(opts, {10, 1, 255, 254})
      refute PeerPolicy.allowed?(opts, lease)
      refute PeerPolicy.allowed?(opts, {10, 2, 0, 5})
    end

    test "after switch to no_internet the lease network is refused" do
      opts = PeerPolicy.listener_opts([@eth_ip], @eth_pool)

      refute PeerPolicy.allowed?(opts, {10, 1, 0, 5})
    end
  end

  describe "unsafe allowed ranges" do
    test "allowing everything still refuses loopback, 0.0.0.0/8 and own address" do
      opts = PeerPolicy.listener_opts([@wlan_ip], [{{0, 0, 0, 0}, 0}])

      assert PeerPolicy.allowed?(opts, {192, 168, 25, 20})
      refute PeerPolicy.allowed?(opts, {127, 0, 0, 1})
      refute PeerPolicy.allowed?(opts, {0, 0, 0, 1})
      refute PeerPolicy.allowed?(opts, @wlan_ip)
    end
  end

  # Helpers

  defp server_opts, do: PeerPolicy.listener_opts([@public_ip])

  defp device_opts, do: PeerPolicy.listener_opts([@wlan_ip, @eth_ip], @wlan_pool ++ @eth_pool)
end

defmodule Chat.Turn.PeerPolicyTest do
  use ExUnit.Case, async: true

  alias Chat.Turn.Config
  alias Chat.Turn.PeerPolicy

  @public_ip {203, 0, 113, 1}

  defp setup_config do
    prev_state = :persistent_term.get(Config, nil)

    :persistent_term.put(Config, %{
      secret: "test",
      enabled: true,
      public_ip: "203.0.113.1",
      public_ip_tuple: @public_ip,
      realm: "test",
      uris: [],
      ttl: 600,
      rate_per_ip_hour: 60
    })

    on_exit(fn ->
      if prev_state, do: :persistent_term.put(Config, prev_state)
    end)
  end

  defp blacklisted?(ip, blacklist) do
    Enum.any?(blacklist, fn subnet -> PeerPolicy.matches?(subnet, ip) end)
  end

  defp whitelisted?(ip, whitelist) do
    Enum.any?(whitelist, fn subnet -> PeerPolicy.matches?(subnet, ip) end)
  end

  defp allowed?(ip, blacklist, whitelist) do
    case {blacklisted?(ip, blacklist), whitelisted?(ip, whitelist)} do
      {true, true} -> true
      {true, false} -> false
      {false, _} -> true
    end
  end

  describe "with empty whitelist, public peer is granted" do
    test "public IPv4 peer passes" do
      setup_config()
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts()
      assert allowed?({8, 8, 8, 8}, bl, wl)
    end
  end

  describe "private addresses are refused" do
    test "192.168.1.10 is refused" do
      setup_config()
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts()
      refute allowed?({192, 168, 1, 10}, bl, wl)
    end

    test "127.0.0.1 is refused" do
      setup_config()
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts()
      refute allowed?({127, 0, 0, 1}, bl, wl)
    end
  end

  describe "host's own TURN_PUBLIC_IP is refused" do
    test "public IP is blacklisted" do
      setup_config()
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts()
      refute allowed?(@public_ip, bl, wl)
    end
  end

  describe "whitelist overrides blacklist" do
    test "192.168.25.20 is granted with whitelist 192.168.25.0/24 minus .1" do
      setup_config()
      whitelist = [{{192, 168, 25, 0}, 24}]
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)

      assert {{192, 168, 25, 0}, 24} in wl
      assert allowed?({192, 168, 25, 20}, bl, wl)
    end

    test "192.168.25.1 is refused when not covered by whitelist" do
      setup_config()
      whitelist = [{{192, 168, 25, 2}, 31}]
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute allowed?({192, 168, 25, 1}, bl, wl)
    end

    test "192.168.24.20 is refused (outside whitelist, in blacklist)" do
      setup_config()
      whitelist = [{{192, 168, 25, 0}, 24}]
      [blacklist_peers: bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute allowed?({192, 168, 24, 20}, bl, wl)
    end
  end

  describe "unsafe whitelist entries are stripped" do
    test "whitelist entry covering loopback is not applied" do
      setup_config()
      whitelist = [{{127, 0, 0, 0}, 8}]
      [blacklist_peers: _bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute {{127, 0, 0, 0}, 8} in wl
    end

    test "whitelist entry covering 0.0.0.0/8 is not applied" do
      setup_config()
      whitelist = [{{0, 0, 0, 0}, 8}]
      [blacklist_peers: _bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute {{0, 0, 0, 0}, 8} in wl
    end

    test "whitelist entry covering host's own address is not applied" do
      setup_config()
      whitelist = [{@public_ip, 32}]
      [blacklist_peers: _bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute {@public_ip, 32} in wl
    end

    test "broad whitelist covering all unsafe ranges is stripped" do
      setup_config()
      whitelist = [{{0, 0, 0, 0}, 0}]
      [blacklist_peers: _bl, whitelist_peers: wl] = PeerPolicy.listener_opts(whitelist)
      refute {{0, 0, 0, 0}, 0} in wl
    end
  end

  describe "no IPv6 entries in blacklist" do
    test "blacklist contains only IPv4 subnets" do
      blacklist = PeerPolicy.blacklist(@public_ip)

      Enum.each(blacklist, fn {{a, b, c, d}, mask} ->
        assert is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d),
               "Expected IPv4 tuple, got: #{inspect({{a, b, c, d}, mask})}"

        assert mask >= 0 and mask <= 32
      end)
    end
  end

  describe "blacklist covers all required RFC ranges" do
    test "all specified ranges are present" do
      blacklist = PeerPolicy.blacklist(nil)

      expected = [
        {{10, 0, 0, 0}, 8},
        {{100, 64, 0, 0}, 10},
        {{127, 0, 0, 0}, 8},
        {{169, 254, 0, 0}, 16},
        {{172, 16, 0, 0}, 12},
        {{192, 0, 0, 0}, 24},
        {{192, 168, 0, 0}, 16},
        {{198, 18, 0, 0}, 15},
        {{240, 0, 0, 0}, 4}
      ]

      Enum.each(expected, fn entry ->
        assert entry in blacklist, "Missing blacklist entry: #{inspect(entry)}"
      end)
    end
  end

  describe "matches?/2" do
    test "exact match" do
      assert PeerPolicy.matches?({{10, 0, 0, 1}, 32}, {10, 0, 0, 1})
    end

    test "subnet match" do
      assert PeerPolicy.matches?({{192, 168, 0, 0}, 16}, {192, 168, 1, 10})
    end

    test "no match" do
      refute PeerPolicy.matches?({{192, 168, 0, 0}, 16}, {10, 0, 0, 1})
    end

    test "/0 matches everything" do
      assert PeerPolicy.matches?({{0, 0, 0, 0}, 0}, {1, 2, 3, 4})
    end
  end
end

defmodule Chat.Turn.LanRelayTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Cidr
  alias Chat.Turn.LanRelay
  alias Chat.Turn.Listener

  @ip {127, 0, 0, 1}
  @allowed Cidr.pool({192, 168, 25, 10}, {192, 168, 25, 250})

  setup do
    on_exit(fn -> LanRelay.stop(@ip) end)
  end

  test "start binds a UDP listener stun accepts and marks the address active" do
    assert :ok = LanRelay.start(@ip, [@ip], @allowed)

    assert LanRelay.active?(@ip)
    assert @ip in LanRelay.active()
    assert {:error, :already_started} = add_raw_listener()
  end

  test "starting twice replaces the listener" do
    assert :ok = LanRelay.start(@ip, [@ip], @allowed)
    assert :ok = LanRelay.start(@ip, [@ip], [])

    assert LanRelay.active?(@ip)
  end

  test "stop releases the address" do
    :ok = LanRelay.start(@ip, [@ip], @allowed)

    assert :ok = LanRelay.stop(@ip)

    refute LanRelay.active?(@ip)
    assert :ok = add_raw_listener()
    Listener.remove(@ip, :udp)
  end

  test "stop on an address without relay is ok" do
    assert :ok = LanRelay.stop({127, 0, 0, 2})
  end

  test "listener options carry the relay address and an empty whitelist" do
    opts = Listener.opts(@ip, [@ip], @allowed)

    assert opts[:turn_ipv4_address] == @ip
    assert opts[:turn_whitelist_peers] == []
    assert is_function(opts[:auth_fun], 2)
  end

  # Helpers

  defp add_raw_listener do
    :stun_listener.add_listener(@ip, Listener.port(), :udp, Listener.opts(@ip, [@ip]))
  end
end

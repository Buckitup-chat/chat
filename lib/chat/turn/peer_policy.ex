defmodule Chat.Turn.PeerPolicy do
  @moduledoc "Builds TURN peer blacklist/whitelist for stun listener options"

  alias Chat.Turn.Config

  @type subnet :: {:inet.ip4_address(), 0..32}

  @rfc1918_blacklist [
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

  @unsafe_ips [
    {0, 0, 0, 1},
    {127, 0, 0, 1}
  ]

  @spec listener_opts(whitelist :: [subnet()]) :: keyword()
  def listener_opts(whitelist \\ []) do
    public_ip = Config.public_ip_tuple()

    [
      blacklist_peers: blacklist(public_ip),
      whitelist_peers: sanitize_whitelist(whitelist, public_ip)
    ]
  end

  @spec blacklist(:inet.ip4_address() | nil) :: [subnet()]
  def blacklist(public_ip) do
    base = @rfc1918_blacklist

    case public_ip do
      {_, _, _, _} -> [host_subnet(public_ip) | base]
      _ -> base
    end
  end

  @spec sanitize_whitelist([subnet()], :inet.ip4_address() | nil) :: [subnet()]
  def sanitize_whitelist(whitelist, public_ip) do
    Enum.reject(whitelist, &unsafe?(&1, public_ip))
  end

  defp unsafe?({_net, _mask} = subnet, public_ip) do
    covers_unsafe_ip?(subnet) or covers_host?(subnet, public_ip)
  end

  defp covers_unsafe_ip?(subnet) do
    Enum.any?(@unsafe_ips, fn ip -> matches?(subnet, ip) end)
  end

  defp covers_host?(_subnet, nil), do: false
  defp covers_host?(subnet, public_ip), do: matches?(subnet, public_ip)

  defp host_subnet(ip), do: {ip, 32}

  @spec matches?(subnet(), :inet.ip4_address()) :: boolean()
  def matches?({{a, b, c, d}, mask}, {e, f, g, h}) do
    import Bitwise
    subnet_int = (a <<< 24) + (b <<< 16) + (c <<< 8) + d
    ip_int = (e <<< 24) + (f <<< 16) + (g <<< 8) + h
    shift = 32 - mask
    subnet_int >>> shift == ip_int >>> shift
  end
end

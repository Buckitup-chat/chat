defmodule Chat.Turn.PeerPolicy do
  @moduledoc """
  Builds the TURN peer access list for stun listener options.

  Allowed LAN ranges are encoded as holes cut out of the blacklist, and
  `turn_whitelist_peers` stays empty. stun checks all peers of one request as
  a set (`turn.erl` `is_blacklisted/3`): a single whitelisted address would
  let every blacklisted address of the same request through. With an empty
  whitelist the check is effectively per address.
  """

  alias Chat.Turn.Cidr

  @type subnet :: Cidr.subnet()

  @base_blacklist [
    {{0, 0, 0, 0}, 8},
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

  @never_allowed [
    {{0, 0, 0, 0}, 8},
    {{127, 0, 0, 0}, 8}
  ]

  @doc """
  Listener options refusing `base_blacklist/0` and `own_ips`, except the
  `allowed` ranges. Loopback, `0.0.0.0/8` and `own_ips` are never allowed.
  """
  @spec listener_opts([:inet.ip4_address()], [subnet()]) :: keyword()
  def listener_opts(own_ips, allowed \\ []) do
    own = Enum.map(own_ips, &{&1, 32})
    holes = Cidr.subtract(allowed, @never_allowed ++ own)

    [
      turn_blacklist_peers: Cidr.subtract(@base_blacklist ++ own, holes),
      turn_whitelist_peers: []
    ]
  end

  @spec base_blacklist() :: [subnet()]
  def base_blacklist, do: @base_blacklist

  @doc "Mirrors stun's per-address check for an empty whitelist"
  @spec allowed?(keyword(), :inet.ip4_address()) :: boolean()
  def allowed?(opts, ip) do
    opts
    |> Keyword.fetch!(:turn_blacklist_peers)
    |> Enum.any?(&Cidr.contains?(&1, ip))
    |> Kernel.not()
  end
end

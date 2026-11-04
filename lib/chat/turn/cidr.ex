defmodule Chat.Turn.Cidr do
  @moduledoc """
  CIDR set operations built on the `ip` library.

  Pool and subtract provide range-to-prefix decomposition and set
  difference that `IP.Prefix` does not offer natively.

  The subnet type matches `:stun`'s `turn:subnet()` so values pass
  through to listener options unchanged.
  """

  import Bitwise

  @type subnet :: {:inet.ip4_address(), 0..32}

  @spec contains?(subnet(), :inet.ip4_address()) :: boolean()
  def contains?(subnet, ip) do
    IP.Prefix.contains_address?(to_prefix(subnet), IP.Address.from_tuple!(ip))
  end

  @doc "Subnet of `ip` with `prefix_len` (host bits cleared)"
  @spec network(:inet.ip4_address(), 0..32) :: subnet()
  def network(ip, prefix_len) do
    prefix = IP.Prefix.new(IP.Address.from_tuple!(ip), prefix_len)
    from_prefix(prefix)
  end

  @doc "Minimal subnets covering `first..last` inclusive"
  @spec pool(:inet.ip4_address(), :inet.ip4_address()) :: [subnet()]
  def pool(first, last) do
    from_range(to_int(first), to_int(last))
  end

  @doc "Subnets covering every address of `subnets` that is not in `holes`"
  @spec subtract([subnet()], [subnet()]) :: [subnet()]
  def subtract(subnets, holes) do
    holes = holes |> Enum.map(&prefix_range/1) |> merge()

    subnets
    |> Enum.map(&prefix_range/1)
    |> merge()
    |> Enum.flat_map(&cut(&1, holes))
    |> Enum.flat_map(fn {lo, hi} -> from_range(lo, hi) end)
  end

  @spec to_range(subnet()) :: {non_neg_integer(), non_neg_integer()}
  def to_range(subnet), do: prefix_range(subnet)

  # Conversions between stun tuples and IP library structs

  defp to_prefix({ip, len}), do: IP.Prefix.new(IP.Address.from_tuple!(ip), len)

  defp from_prefix(prefix) do
    {IP.Address.to_tuple(IP.Prefix.first(prefix)), IP.Prefix.length(prefix)}
  end

  defp prefix_range(subnet) do
    prefix = to_prefix(subnet)
    {to_int(prefix, :first), to_int(prefix, :last)}
  end

  defp to_int(prefix, :first), do: prefix |> IP.Prefix.first() |> IP.Address.to_integer()
  defp to_int(prefix, :last), do: prefix |> IP.Prefix.last() |> IP.Address.to_integer()

  defp to_int(ip_tuple), do: ip_tuple |> IP.Address.from_tuple!() |> IP.Address.to_integer()
  defp from_int(n), do: n |> IP.Address.from_integer!(4) |> IP.Address.to_tuple()

  # Range set operations (pure integer math — no IP library equivalent)

  defp cut(range, holes) do
    Enum.reduce(holes, [range], fn hole, acc -> Enum.flat_map(acc, &cut_one(&1, hole)) end)
  end

  defp cut_one({lo, hi}, {h_lo, h_hi}) when h_hi < lo or h_lo > hi, do: [{lo, hi}]

  defp cut_one({lo, hi}, {h_lo, h_hi}) do
    [{lo, h_lo - 1}, {h_hi + 1, hi}]
    |> Enum.filter(fn {l, h} -> l <= h end)
  end

  defp merge(ranges) do
    ranges
    |> Enum.sort()
    |> Enum.reduce([], fn
      {lo, hi}, [{p_lo, p_hi} | rest] when lo <= p_hi + 1 -> [{p_lo, max(hi, p_hi)} | rest]
      range, acc -> [range | acc]
    end)
    |> Enum.reverse()
  end

  defp from_range(lo, hi) when lo > hi, do: []

  defp from_range(lo, hi) do
    size = largest_block(lo, hi - lo + 1)
    [{from_int(lo), 32 - size} | from_range(lo + (1 <<< size), hi)]
  end

  defp largest_block(lo, count) do
    32
    |> Range.new(0, -1)
    |> Enum.find(fn bits -> rem(lo, 1 <<< bits) == 0 and 1 <<< bits <= count end)
  end
end

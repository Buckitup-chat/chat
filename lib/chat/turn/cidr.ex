defmodule Chat.Turn.Cidr do
  @moduledoc """
  IPv4 range math over `{ip_tuple, prefix_len}` subnets.

  Ranges are handled as inclusive integer intervals, so subtraction and
  pool → CIDR decomposition are exact.
  """

  import Bitwise

  @type subnet :: {:inet.ip4_address(), 0..32}

  @max 0xFFFFFFFF

  @spec contains?(subnet(), :inet.ip4_address()) :: boolean()
  def contains?(subnet, ip) do
    {lo, hi} = to_range(subnet)
    n = to_int(ip)
    n >= lo and n <= hi
  end

  @doc "Subnet of `ip` with `prefix_len` (host bits cleared)"
  @spec network(:inet.ip4_address(), 0..32) :: subnet()
  def network(ip, prefix_len) do
    {ip |> to_int() |> band(mask(prefix_len)) |> from_int(), prefix_len}
  end

  @doc "Minimal subnets covering `first..last` inclusive"
  @spec pool(:inet.ip4_address(), :inet.ip4_address()) :: [subnet()]
  def pool(first, last), do: from_range(to_int(first), to_int(last))

  @doc "Subnets covering every address of `subnets` that is not in `holes`"
  @spec subtract([subnet()], [subnet()]) :: [subnet()]
  def subtract(subnets, holes) do
    holes = holes |> Enum.map(&to_range/1) |> merge()

    subnets
    |> Enum.map(&to_range/1)
    |> merge()
    |> Enum.flat_map(&cut(&1, holes))
    |> Enum.flat_map(fn {lo, hi} -> from_range(lo, hi) end)
  end

  @spec to_range(subnet()) :: {non_neg_integer(), non_neg_integer()}
  def to_range({ip, prefix_len}) do
    lo = ip |> to_int() |> band(mask(prefix_len))
    {lo, lo + (1 <<< (32 - prefix_len)) - 1}
  end

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

  defp mask(prefix_len), do: @max <<< (32 - prefix_len) &&& @max

  defp to_int({a, b, c, d}), do: (a <<< 24) + (b <<< 16) + (c <<< 8) + d

  defp from_int(n), do: {n >>> 24 &&& 255, n >>> 16 &&& 255, n >>> 8 &&& 255, n &&& 255}
end

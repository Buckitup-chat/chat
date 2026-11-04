defmodule Chat.Turn.CidrTest do
  use ExUnit.Case, async: true

  alias Chat.Turn.Cidr

  describe "network/2" do
    test "clears host bits" do
      assert Cidr.network({10, 1, 2, 3}, 16) == {{10, 1, 0, 0}, 16}
      assert Cidr.network({192, 168, 25, 1}, 24) == {{192, 168, 25, 0}, 24}
    end
  end

  describe "pool/2" do
    test "covers exactly .10 to .250" do
      subnets = Cidr.pool({192, 168, 25, 10}, {192, 168, 25, 250})

      assert covered(subnets) == Enum.to_list(10..250)
      refute covers?(subnets, {192, 168, 25, 9})
      refute covers?(subnets, {192, 168, 25, 251})
    end

    test "a single address is one /32" do
      assert Cidr.pool({10, 0, 0, 7}, {10, 0, 0, 7}) == [{{10, 0, 0, 7}, 32}]
    end
  end

  describe "subtract/2" do
    test "lease /16 minus own address leaves everything else" do
      subnets = Cidr.subtract([{{10, 1, 0, 0}, 16}], [{{10, 1, 2, 3}, 32}])

      assert covers?(subnets, {10, 1, 0, 0})
      assert covers?(subnets, {10, 1, 2, 2})
      assert covers?(subnets, {10, 1, 2, 4})
      assert covers?(subnets, {10, 1, 255, 255})
      refute covers?(subnets, {10, 1, 2, 3})
      assert total_size(subnets) == 65_535
    end

    test "hole covering the whole range leaves nothing" do
      assert Cidr.subtract([{{192, 168, 25, 0}, 24}], [{{192, 168, 0, 0}, 16}]) == []
    end

    test "disjoint hole keeps the range intact" do
      assert Cidr.subtract([{{10, 0, 0, 0}, 8}], [{{192, 168, 0, 0}, 16}]) ==
               [{{10, 0, 0, 0}, 8}]
    end

    test "overlapping inputs are merged" do
      assert Cidr.subtract([{{10, 0, 0, 0}, 8}, {{10, 1, 0, 0}, 16}], []) ==
               [{{10, 0, 0, 0}, 8}]
    end

    test "matches set difference on random ranges" do
      for _ <- 1..50 do
        a = random_subnet()
        b = random_subnet()
        result = Cidr.subtract([a], [b])

        for ip <- sample_ips(a) do
          assert covers?(result, ip) == not Cidr.contains?(b, ip)
        end
      end
    end
  end

  # Helpers

  defp covers?(subnets, ip), do: Enum.any?(subnets, &Cidr.contains?(&1, ip))

  defp covered(subnets) do
    for d <- 0..255, covers?(subnets, {192, 168, 25, d}), do: d
  end

  defp total_size(subnets) do
    subnets
    |> Enum.map(&Cidr.to_range/1)
    |> Enum.map(fn {lo, hi} -> hi - lo + 1 end)
    |> Enum.sum()
  end

  defp random_subnet do
    Cidr.network({10, 1, :rand.uniform(4) - 1, :rand.uniform(256) - 1}, 22 + :rand.uniform(10))
  end

  defp sample_ips({{a, b, c, _}, _} = subnet) do
    for c2 <- max(c - 4, 0)..min(c + 4, 255),
        d <- [0, 1, 2, 127, 128, 254, 255],
        ip = {a, b, c2, d},
        Cidr.contains?(subnet, ip),
        do: ip
  end
end

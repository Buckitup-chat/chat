defmodule Chat.Data.Types.OriginOrderHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.OriginOrderHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "org_ord_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid hash" do
      assert {:ok, @valid_hash} = OriginOrderHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "org_ord_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = OriginOrderHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = OriginOrderHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = OriginOrderHash.cast("org_ord_abcdef")
    end

    test "rejects invalid hex" do
      assert :error = OriginOrderHash.cast("org_ord_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = OriginOrderHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid hash" do
      assert {:ok, @valid_hash} = OriginOrderHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = OriginOrderHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid hash" do
      assert {:ok, @valid_hash} = OriginOrderHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = OriginOrderHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = OriginOrderHash.from_binary(binary)

      assert {:ok, ^hash} = OriginOrderHash.cast(hash)
      assert OriginOrderHash.to_binary(hash) == binary
    end
  end
end

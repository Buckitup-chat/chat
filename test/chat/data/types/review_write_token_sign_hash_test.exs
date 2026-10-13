defmodule Chat.Data.Types.ReviewWriteTokenSignHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.ReviewWriteTokenSignHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "rwt_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid hash" do
      assert {:ok, @valid_hash} = ReviewWriteTokenSignHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "rwt_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = ReviewWriteTokenSignHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = ReviewWriteTokenSignHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = ReviewWriteTokenSignHash.cast("rwt_abcdef")
    end

    test "rejects invalid hex" do
      assert :error = ReviewWriteTokenSignHash.cast("rwt_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = ReviewWriteTokenSignHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid hash" do
      assert {:ok, @valid_hash} = ReviewWriteTokenSignHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = ReviewWriteTokenSignHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid hash" do
      assert {:ok, @valid_hash} = ReviewWriteTokenSignHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = ReviewWriteTokenSignHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = ReviewWriteTokenSignHash.from_binary(binary)

      assert {:ok, ^hash} = ReviewWriteTokenSignHash.cast(hash)
      assert ReviewWriteTokenSignHash.to_binary(hash) == binary
    end
  end
end

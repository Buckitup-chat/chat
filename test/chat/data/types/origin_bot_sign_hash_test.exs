defmodule Chat.Data.Types.OriginBotSignHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.OriginBotSignHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "ob_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid hash" do
      assert {:ok, @valid_hash} = OriginBotSignHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "ob_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = OriginBotSignHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = OriginBotSignHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = OriginBotSignHash.cast("ob_abcdef")
    end

    test "rejects invalid hex" do
      assert :error = OriginBotSignHash.cast("ob_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = OriginBotSignHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid hash" do
      assert {:ok, @valid_hash} = OriginBotSignHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = OriginBotSignHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid hash" do
      assert {:ok, @valid_hash} = OriginBotSignHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = OriginBotSignHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = OriginBotSignHash.from_binary(binary)

      assert {:ok, ^hash} = OriginBotSignHash.cast(hash)
      assert OriginBotSignHash.to_binary(hash) == binary
    end
  end
end

defmodule Chat.Data.Types.FileChunkDataHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.FileChunkDataHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "fd_" <> String.duplicate("ab", 64)

  describe "cast/1" do
    test "accepts valid hash" do
      assert {:ok, @valid_hash} = FileChunkDataHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "fd_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = FileChunkDataHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = FileChunkDataHash.cast("xx_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = FileChunkDataHash.cast("fd_abcd")
    end

    test "rejects invalid hex" do
      assert :error = FileChunkDataHash.cast("fd_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = FileChunkDataHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid hash" do
      assert {:ok, @valid_hash} = FileChunkDataHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = FileChunkDataHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid hash" do
      assert {:ok, @valid_hash} = FileChunkDataHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = FileChunkDataHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = FileChunkDataHash.from_binary(binary)

      assert {:ok, ^hash} = FileChunkDataHash.cast(hash)
      assert FileChunkDataHash.to_binary(hash) == binary
    end
  end
end

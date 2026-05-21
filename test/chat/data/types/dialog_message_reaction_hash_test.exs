defmodule Chat.Data.Types.DialogMessageReactionHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.DialogMessageReactionHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "dmr_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid reaction_hash" do
      assert {:ok, @valid_hash} = DialogMessageReactionHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "dmr_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = DialogMessageReactionHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = DialogMessageReactionHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = DialogMessageReactionHash.cast("dmr_abcdef")
    end

    test "rejects nil" do
      assert :error = DialogMessageReactionHash.cast(nil)
    end
  end

  describe "dump/1 and load/1" do
    test "round-trips" do
      assert {:ok, @valid_hash} = DialogMessageReactionHash.dump(@valid_hash)
      assert {:ok, @valid_hash} = DialogMessageReactionHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogMessageReactionHash.dump("bad")
      assert :error = DialogMessageReactionHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = DialogMessageReactionHash.from_binary(binary)

      assert {:ok, ^hash} = DialogMessageReactionHash.cast(hash)
      assert DialogMessageReactionHash.to_binary(hash) == binary
    end
  end
end

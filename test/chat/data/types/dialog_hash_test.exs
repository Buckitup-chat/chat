defmodule Chat.Data.Types.DialogHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.DialogHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "di_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid dialog_hash" do
      assert {:ok, @valid_hash} = DialogHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "di_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = DialogHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = DialogHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = DialogHash.cast("di_abcdef")
    end

    test "rejects invalid hex" do
      assert :error = DialogHash.cast("di_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = DialogHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid dialog_hash" do
      assert {:ok, @valid_hash} = DialogHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid dialog_hash" do
      assert {:ok, @valid_hash} = DialogHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      dialog_hash = DialogHash.from_binary(binary)

      assert {:ok, ^dialog_hash} = DialogHash.cast(dialog_hash)
      assert DialogHash.to_binary(dialog_hash) == binary
    end
  end
end

defmodule Chat.Data.Types.DialogMessageReceiptHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.DialogMessageReceiptHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "dmrc_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid receipt_hash" do
      assert {:ok, @valid_hash} = DialogMessageReceiptHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "dmrc_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = DialogMessageReceiptHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = DialogMessageReceiptHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = DialogMessageReceiptHash.cast("dmrc_abcdef")
    end

    test "rejects nil" do
      assert :error = DialogMessageReceiptHash.cast(nil)
    end
  end

  describe "dump/1 and load/1" do
    test "round-trips" do
      assert {:ok, @valid_hash} = DialogMessageReceiptHash.dump(@valid_hash)
      assert {:ok, @valid_hash} = DialogMessageReceiptHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogMessageReceiptHash.dump("bad")
      assert :error = DialogMessageReceiptHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = DialogMessageReceiptHash.from_binary(binary)

      assert {:ok, ^hash} = DialogMessageReceiptHash.cast(hash)
      assert DialogMessageReceiptHash.to_binary(hash) == binary
    end
  end
end

defmodule Chat.Data.Types.DialogMessageSignHashTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.DialogMessageSignHash

  @valid_hex String.duplicate("ab", 64)
  @valid_hash "dms_" <> @valid_hex

  describe "cast/1" do
    test "accepts valid sign_hash" do
      assert {:ok, @valid_hash} = DialogMessageSignHash.cast(@valid_hash)
    end

    test "lowercases hex on cast" do
      upper = "dms_" <> String.duplicate("AB", 64)
      assert {:ok, @valid_hash} = DialogMessageSignHash.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = DialogMessageSignHash.cast("x_" <> @valid_hex)
    end

    test "rejects wrong length" do
      assert :error = DialogMessageSignHash.cast("dms_abcdef")
    end

    test "rejects invalid hex" do
      assert :error = DialogMessageSignHash.cast("dms_" <> String.duplicate("zz", 64))
    end

    test "rejects nil" do
      assert :error = DialogMessageSignHash.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid sign_hash" do
      assert {:ok, @valid_hash} = DialogMessageSignHash.dump(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogMessageSignHash.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid sign_hash" do
      assert {:ok, @valid_hash} = DialogMessageSignHash.load(@valid_hash)
    end

    test "rejects invalid" do
      assert :error = DialogMessageSignHash.load("bad")
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 64-byte binary" do
      binary = :crypto.strong_rand_bytes(64)
      hash = DialogMessageSignHash.from_binary(binary)

      assert {:ok, ^hash} = DialogMessageSignHash.cast(hash)
      assert DialogMessageSignHash.to_binary(hash) == binary
    end
  end
end

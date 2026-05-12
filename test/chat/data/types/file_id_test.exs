defmodule Chat.Data.Types.FileIdTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.FileId

  describe "cast/1" do
    test "accepts valid file_id" do
      assert {:ok, "f_" <> _} = FileId.cast("f_0123456789abcdef0123456789abcdef")
    end

    test "lowercases hex on cast" do
      assert {:ok, "f_0123456789abcdef0123456789abcdef"} =
               FileId.cast("f_0123456789ABCDEF0123456789ABCDEF")
    end

    test "rejects wrong prefix" do
      assert :error = FileId.cast("x_0123456789abcdef0123456789abcdef")
    end

    test "rejects wrong length" do
      assert :error = FileId.cast("f_0123456789abcdef")
    end

    test "rejects invalid hex" do
      assert :error = FileId.cast("f_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
    end

    test "rejects nil" do
      assert :error = FileId.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid file_id" do
      assert {:ok, "f_0123456789abcdef0123456789abcdef"} =
               FileId.dump("f_0123456789abcdef0123456789abcdef")
    end

    test "rejects invalid" do
      assert :error = FileId.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid file_id" do
      assert {:ok, "f_0123456789abcdef0123456789abcdef"} =
               FileId.load("f_0123456789abcdef0123456789abcdef")
    end

    test "rejects invalid" do
      assert :error = FileId.load("bad")
    end
  end

  describe "generate/0" do
    test "returns a valid file_id" do
      file_id = FileId.generate()
      assert {:ok, ^file_id} = FileId.cast(file_id)
    end

    test "generates unique ids" do
      ids = for _ <- 1..100, do: FileId.generate()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "from_binary/1 and to_binary/1" do
    test "round-trips 16-byte binary" do
      binary = :crypto.strong_rand_bytes(16)
      file_id = FileId.from_binary(binary)

      assert {:ok, ^file_id} = FileId.cast(file_id)
      assert FileId.to_binary(file_id) == binary
    end
  end
end

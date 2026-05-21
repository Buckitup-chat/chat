defmodule Chat.Data.Types.DialogMessageIdTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.DialogMessageId

  @valid_id "dmsg_01234567-abcd-7def-89ab-0123456789ab"

  describe "cast/1" do
    test "accepts valid dialog_message_id" do
      assert {:ok, @valid_id} = DialogMessageId.cast(@valid_id)
    end

    test "lowercases on cast" do
      upper = "dmsg_01234567-ABCD-7DEF-89AB-0123456789AB"
      assert {:ok, @valid_id} = DialogMessageId.cast(upper)
    end

    test "rejects wrong prefix" do
      assert :error = DialogMessageId.cast("x_01234567-abcd-7def-89ab-0123456789ab")
    end

    test "rejects missing dashes" do
      assert :error = DialogMessageId.cast("dmsg_01234567abcd7def89ab0123456789ab")
    end

    test "rejects non-v7 uuid (wrong version nibble)" do
      assert :error = DialogMessageId.cast("dmsg_01234567-abcd-4def-89ab-0123456789ab")
    end

    test "rejects nil" do
      assert :error = DialogMessageId.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps valid dialog_message_id" do
      assert {:ok, @valid_id} = DialogMessageId.dump(@valid_id)
    end

    test "rejects invalid" do
      assert :error = DialogMessageId.dump("bad")
    end
  end

  describe "load/1" do
    test "loads valid dialog_message_id" do
      assert {:ok, @valid_id} = DialogMessageId.load(@valid_id)
    end

    test "rejects invalid" do
      assert :error = DialogMessageId.load("bad")
    end
  end

  describe "generate/0" do
    test "returns a valid dialog_message_id" do
      id = DialogMessageId.generate()
      assert {:ok, ^id} = DialogMessageId.cast(id)
    end

    test "generates unique ids" do
      ids = for _ <- 1..100, do: DialogMessageId.generate()
      assert length(Enum.uniq(ids)) == 100
    end
  end
end

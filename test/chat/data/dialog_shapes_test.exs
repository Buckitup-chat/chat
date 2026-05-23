defmodule Chat.Data.DialogShapesTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Schemas.DialogMessageVersion
  alias Chat.Data.Shapes.DialogKeys
  alias Chat.Data.Shapes.DialogMessageReactions
  alias Chat.Data.Shapes.DialogMessageReceipts
  alias Chat.Data.Shapes.DialogMessages
  alias Chat.Data.Types.DialogMessageSignHash

  describe "DialogKeys shape" do
    test "shape_name" do
      assert DialogKeys.shape_name() == :dialog_keys
    end

    test "schema_module" do
      assert DialogKeys.schema_module() == DialogKey
    end

    test "sync_required_parents returns user_card dependency" do
      assert [{:user_card, "u_abc"}] =
               DialogKeys.sync_required_parents(:insert, %{sender_hash: "u_abc"})
    end
  end

  describe "DialogMessages shape" do
    test "shape_name" do
      assert DialogMessages.shape_name() == :dialog_messages
    end

    test "schema_module" do
      assert DialogMessages.schema_module() == DialogMessage
    end

    test "versions_schema" do
      assert DialogMessages.versions_schema() == DialogMessageVersion
    end

    test "sync_required_parents returns user_card and dialog_keys dependencies" do
      assert [{:user_card, "u_abc"}, {:dialog_keys, {"di_def", "u_abc"}}] =
               DialogMessages.sync_required_parents(:insert, %{
                 sender_hash: "u_abc",
                 dialog_hash: "di_def"
               })
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()

      message = %DialogMessage{sign_b64: sign_b64}
      result = DialogMessages.sync_derive_fields(message)

      assert result.sign_hash == expected_hash
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      message = %DialogMessage{sign_b64: nil}
      result = DialogMessages.sync_derive_fields(message)

      assert result.sign_hash == nil
    end
  end

  describe "DialogMessageReactions shape" do
    test "shape_name" do
      assert DialogMessageReactions.shape_name() == :dialog_message_reactions
    end

    test "schema_module" do
      assert DialogMessageReactions.schema_module() == DialogMessageReaction
    end

    test "sync_required_parents returns user_card dependency for reactor" do
      assert [{:user_card, "u_abc"}] =
               DialogMessageReactions.sync_required_parents(:insert, %{reactor_hash: "u_abc"})
    end
  end

  describe "DialogMessageReceipts shape" do
    test "shape_name" do
      assert DialogMessageReceipts.shape_name() == :dialog_message_receipts
    end

    test "schema_module" do
      assert DialogMessageReceipts.schema_module() == DialogMessageReceipt
    end

    test "sync_required_parents returns user_card dependency for peer" do
      assert [{:user_card, "u_abc"}] =
               DialogMessageReceipts.sync_required_parents(:insert, %{peer_hash: "u_abc"})
    end
  end
end

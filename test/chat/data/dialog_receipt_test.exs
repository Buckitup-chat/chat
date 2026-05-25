defmodule Chat.Data.DialogReceiptTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReceiptHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    alice = User.generate_pq_identity("Alice")
    alice_card = insert_signed_user_card(alice)

    {:ok, alice: alice, alice_hash: alice_card.user_hash}
  end

  describe "valid receipt — peer sync" do
    test "is persisted", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "delivered")
      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, receipt)

      assert Dialog.get_receipt(receipt.receipt_hash) != nil
    end

    test "insert-only — duplicate PK is noop", ctx do
      receipt_hash = generate_receipt_hash()

      r1 =
        signed_receipt(ctx.alice, ctx.alice_hash, "delivered",
          receipt_hash: receipt_hash,
          owner_timestamp: 100
        )

      r2 =
        signed_receipt(ctx.alice, ctx.alice_hash, "delivered",
          receipt_hash: receipt_hash,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, r1)
      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, r2)

      persisted = Dialog.get_receipt(receipt_hash)
      assert persisted.owner_timestamp == 100
    end

    test "accepts read type", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "read")
      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, receipt)

      persisted = Dialog.get_receipt(receipt.receipt_hash)
      assert persisted.type == "read"
    end
  end

  describe "tampered receipt — peer sync" do
    test "tampered field is not persisted", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "delivered")
      tampered = %{receipt | type: "read"}

      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, tampered)

      assert Dialog.get_receipt(receipt.receipt_hash) == nil
    end
  end

  describe "self-receipt — peer sync" do
    setup ctx do
      bob = User.generate_pq_identity("Bob")
      bob_card = insert_signed_user_card(bob)

      dialog_hash = compute_dialog_hash(ctx.alice_hash, bob_card.user_hash)
      insert_dialog_key(ctx.alice, dialog_hash, ctx.alice_hash, bob_card.user_hash)
      msg = signed_message(ctx.alice, dialog_hash, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)

      {:ok,
       bob: bob,
       bob_hash: bob_card.user_hash,
       dialog_hash: dialog_hash,
       message_id: msg.message_id}
    end

    test "author cannot receipt own message", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "delivered", message_id: ctx.message_id)
      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, receipt)

      assert Dialog.get_receipt(receipt.receipt_hash) == nil
    end

    test "peer can receipt author's message", ctx do
      receipt = signed_receipt(ctx.bob, ctx.bob_hash, "delivered", message_id: ctx.message_id)
      {:ok, _} = ShapeWriter.write(:dialog_message_receipts, :insert, receipt)

      assert Dialog.get_receipt(receipt.receipt_hash) != nil
    end
  end

  describe "signable protocol" do
    test "signable_fields excludes sign_b64 and __meta__, has no deleted_flag" do
      receipt = %DialogMessageReceipt{
        receipt_hash: "dmrc_" <> String.duplicate("ab", 64),
        dialog_hash: "di_" <> String.duplicate("ab", 64),
        message_id: DialogMessageId.generate(),
        peer_hash: "u_" <> String.duplicate("cd", 64),
        type: "delivered",
        message_sign_hash: "dms_" <> String.duplicate("ef", 64),
        owner_timestamp: 1,
        sign_b64: "sig"
      }

      fields = Signable.signable_fields(receipt)
      refute Map.has_key?(fields, :sign_b64)
      refute Map.has_key?(fields, :__meta__)
      refute Map.has_key?(fields, :deleted_flag)
      assert Map.has_key?(fields, :receipt_hash)
      assert Map.has_key?(fields, :peer_hash)
      assert Map.has_key?(fields, :type)
    end
  end

  # --- Helpers ---

  defp compute_dialog_hash(hash_a, hash_b) do
    sorted = Enum.sort([hash_a, hash_b])
    binary = :crypto.hash(:sha3_512, Enum.join(sorted))
    DialogHash.from_binary(binary)
  end

  defp signed_message(identity, dialog_hash, sender_hash) do
    %Chat.Data.Schemas.DialogMessage{
      message_id: DialogMessageId.generate(),
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      content_b64: :crypto.strong_rand_bytes(32),
      deleted_flag: false,
      refs_map_b64: nil,
      parent_sign_hash: nil,
      owner_timestamp: System.os_time(:millisecond)
    }
    |> sign_message_with_key(identity.sign_skey)
  end

  defp sign_message_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp generate_receipt_hash do
    binary = :crypto.strong_rand_bytes(64)
    DialogMessageReceiptHash.from_binary(binary)
  end

  defp build_receipt(peer_hash, type, attrs \\ []) do
    %DialogMessageReceipt{
      receipt_hash: Keyword.get(attrs, :receipt_hash, generate_receipt_hash()),
      dialog_hash: "di_" <> String.duplicate("ab", 64),
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      peer_hash: peer_hash,
      type: type,
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp signed_receipt(identity, peer_hash, type, attrs \\ []) do
    build_receipt(peer_hash, type, attrs)
    |> sign_with_key(identity.sign_skey)
  end

  defp insert_signed_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_card(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp sign_card(card, sign_skey) do
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{card | sign_b64: sign_b64}
  end

  defp insert_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk =
      %Chat.Data.Schemas.DialogKey{
        dialog_hash: dialog_hash,
        sender_hash: sender_hash,
        peer_hash: peer_hash,
        peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
        peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
        owner_timestamp: System.os_time(:millisecond),
        deleted_flag: false
      }
      |> sign_with_key(identity.sign_skey)

    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)
    dk
  end
end

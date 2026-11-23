defmodule Chat.Data.DialogMembershipTest do
  @moduledoc "Only the two participants of a dialog can write into it (security issue 06)."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageReceiptHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Phoenix.Sync.Writer.Operation

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    [alice, bob, mallory] = Enum.map(["Alice", "Bob", "Mallory"], &User.generate_pq_identity/1)
    [a, b, m] = Enum.map([alice, bob, mallory], &insert_signed_user_card(&1).user_hash)

    di_ab = DialogHash.for_pair(a, b)
    write!(:dialog_keys, signed_key(alice, di_ab, a, b))
    write!(:dialog_keys, signed_key(bob, di_ab, b, a))
    msg = signed_message(alice, di_ab, a)
    write!(:dialog_messages, msg)

    {:ok,
     alice: alice,
     bob: bob,
     mallory: mallory,
     a: a,
     b: b,
     m: m,
     di_ab: di_ab,
     message_id: msg.message_id}
  end

  describe "DialogHash.for_pair/2" do
    test "is order-independent and follows the spec", ctx do
      [first, second] = Enum.sort([ctx.a, ctx.b])
      expected = DialogHash.from_binary(:crypto.hash(:sha3_512, first <> second))

      assert DialogHash.for_pair(ctx.a, ctx.b) == expected
      assert DialogHash.for_pair(ctx.b, ctx.a) == expected
    end
  end

  describe "dialog_keys bound to its pair" do
    test "ingest refuses a key lifted into another dialog", ctx do
      key = signed_key(ctx.mallory, ctx.di_ab, ctx.m, ctx.a)

      changeset = Validation.dialog_key_validate(%DialogKey{}, to_changes(key), :insert)

      refute changeset.valid?
      assert {"does not match sender/peer pair", _} = changeset.errors[:dialog_hash]
    end

    test "peer sync refuses a key lifted into another dialog", ctx do
      write!(:dialog_keys, signed_key(ctx.mallory, ctx.di_ab, ctx.m, ctx.a))

      assert Dialog.get_dialog_key(ctx.di_ab, ctx.m) == nil
    end

    test "a key for the right pair is accepted", ctx do
      di_am = DialogHash.for_pair(ctx.a, ctx.m)
      write!(:dialog_keys, signed_key(ctx.mallory, di_am, ctx.m, ctx.a))

      assert %DialogKey{} = Dialog.get_dialog_key(di_am, ctx.m)
    end
  end

  describe "non-participant messages" do
    test "ingest refuses", ctx do
      op = insert_op(%{"sender_hash" => ctx.m, "dialog_hash" => ctx.di_ab})

      assert {:error, _} = Validation.message_allowed(op, pop(ctx.mallory))
    end

    test "peer sync refuses", ctx do
      msg = signed_message(ctx.mallory, ctx.di_ab, ctx.m)
      write!(:dialog_messages, msg)

      assert Dialog.get_message(msg.message_id) == nil
    end
  end

  describe "non-participant reactions" do
    test "ingest refuses", ctx do
      op = insert_op(%{"reactor_hash" => ctx.m, "dialog_hash" => ctx.di_ab})

      assert {:error, "not a dialog participant"} =
               Validation.reaction_allowed(op, pop(ctx.mallory))
    end

    test "peer sync refuses", ctx do
      reaction = signed_reaction(ctx.mallory, ctx.di_ab, ctx.m, ctx.message_id)
      write!(:dialog_message_reactions, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) == nil
    end

    test "a participant's reaction is accepted", ctx do
      reaction = signed_reaction(ctx.bob, ctx.di_ab, ctx.b, ctx.message_id)
      write!(:dialog_message_reactions, reaction)

      assert %DialogMessageReaction{} = Dialog.get_reaction(reaction.reaction_hash)
    end
  end

  describe "non-participant receipts" do
    test "ingest refuses", ctx do
      op = receipt_op(ctx.m, ctx.di_ab, ctx.message_id)

      assert {:error, "not a dialog participant"} =
               Validation.receipt_allowed(op, pop(ctx.mallory))
    end

    test "peer sync refuses", ctx do
      receipt = signed_receipt(ctx.mallory, ctx.di_ab, ctx.m, ctx.message_id)
      write!(:dialog_message_receipts, receipt)

      assert Dialog.get_receipt(receipt.receipt_hash) == nil
    end

    test "a participant's receipt is accepted", ctx do
      receipt = signed_receipt(ctx.bob, ctx.di_ab, ctx.b, ctx.message_id)
      write!(:dialog_message_receipts, receipt)

      assert %DialogMessageReceipt{} = Dialog.get_receipt(receipt.receipt_hash)
    end
  end

  describe "reactions and receipts on a message of another dialog" do
    setup ctx do
      di_am = DialogHash.for_pair(ctx.a, ctx.m)
      write!(:dialog_keys, signed_key(ctx.mallory, di_am, ctx.m, ctx.a))
      {:ok, di_am: di_am}
    end

    test "reaction is refused on ingest and peer sync", ctx do
      op =
        insert_op(%{
          "reactor_hash" => ctx.m,
          "dialog_hash" => ctx.di_am,
          "message_id" => ctx.message_id
        })

      assert {:error, "message belongs to another dialog"} =
               Validation.reaction_allowed(op, pop(ctx.mallory))

      reaction = signed_reaction(ctx.mallory, ctx.di_am, ctx.m, ctx.message_id)
      write!(:dialog_message_reactions, reaction)
      assert Dialog.get_reaction(reaction.reaction_hash) == nil
    end

    test "receipt is refused on ingest and peer sync", ctx do
      op = receipt_op(ctx.m, ctx.di_am, ctx.message_id)

      assert {:error, "message belongs to another dialog"} =
               Validation.receipt_allowed(op, pop(ctx.mallory))

      receipt = signed_receipt(ctx.mallory, ctx.di_am, ctx.m, ctx.message_id)
      write!(:dialog_message_receipts, receipt)
      assert Dialog.get_receipt(receipt.receipt_hash) == nil
    end
  end

  # --- Helpers ---

  defp write!(shape, row), do: {:ok, _} = ShapeWriter.write(shape, :insert, row)

  defp to_changes(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])

  defp insert_op(changes), do: %Operation{operation: :insert, changes: changes}

  defp receipt_op(peer_hash, dialog_hash, message_id) do
    insert_op(%{
      "peer_hash" => peer_hash,
      "dialog_hash" => dialog_hash,
      "message_id" => message_id
    })
  end

  defp pop(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    %{challenge: challenge, signature: EnigmaPq.sign(challenge, identity.sign_skey)}
  end

  defp sign(struct, identity) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp insert_signed_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign(identity)
    write!(:user_card, card)
    card
  end

  defp signed_key(identity, dialog_hash, sender_hash, peer_hash) do
    %DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }
    |> sign(identity)
  end

  defp signed_message(identity, dialog_hash, sender_hash) do
    message =
      %DialogMessage{
        message_id: DialogMessageId.generate(),
        dialog_hash: dialog_hash,
        sender_hash: sender_hash,
        content_b64: :crypto.strong_rand_bytes(32),
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      }
      |> sign(identity)

    %{
      message
      | sign_hash: message.sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    }
  end

  defp signed_reaction(identity, dialog_hash, reactor_hash, message_id) do
    %DialogMessageReaction{
      reaction_hash: :crypto.strong_rand_bytes(64) |> DialogMessageReactionHash.from_binary(),
      dialog_hash: dialog_hash,
      message_id: message_id,
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      reactor_hash: reactor_hash,
      type_b64: :crypto.strong_rand_bytes(24),
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }
    |> sign(identity)
  end

  defp signed_receipt(identity, dialog_hash, peer_hash, message_id) do
    %DialogMessageReceipt{
      receipt_hash: :crypto.strong_rand_bytes(64) |> DialogMessageReceiptHash.from_binary(),
      dialog_hash: dialog_hash,
      message_id: message_id,
      peer_hash: peer_hash,
      type: "read",
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      owner_timestamp: System.os_time(:millisecond)
    }
    |> sign(identity)
  end
end

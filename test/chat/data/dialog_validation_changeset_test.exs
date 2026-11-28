defmodule Chat.Data.DialogValidationChangesetTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.DialogDataFixtures,
    only: [
      alice_and_bob: 1,
      generate_reaction_hash: 0,
      insert_alice_message: 1,
      join_dialog: 1,
      signed_dialog_key: 5,
      signed_reaction: 3,
      signed_receipt: 4
    ]

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Types.DialogMessageId
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup :alice_and_bob

  describe "dialog_key_validate/3" do
    test "valid insert returns valid changeset", ctx do
      dk = alice_dialog_key(ctx, System.os_time(:millisecond))

      changeset = Validation.dialog_key_validate(%DialogKey{}, to_changes(dk), :insert)
      assert changeset.valid?
    end

    test "tampered insert returns invalid changeset", ctx do
      dk = alice_dialog_key(ctx, System.os_time(:millisecond))
      changes = dk |> to_changes() |> Map.put(:peer_hash, ctx.alice_hash)

      changeset = Validation.dialog_key_validate(%DialogKey{}, changes, :insert)
      refute changeset.valid?
    end

    test "valid update returns valid changeset", ctx do
      existing = persist_alice_dialog_key(ctx, 100)
      dk2 = alice_dialog_key(ctx, 200)

      changeset = Validation.dialog_key_validate(existing, to_changes(dk2), :update)
      assert changeset.valid?
    end

    test "stale update returns invalid changeset", ctx do
      existing = persist_alice_dialog_key(ctx, 200)
      dk2 = alice_dialog_key(ctx, 100)

      changeset = Validation.dialog_key_validate(existing, to_changes(dk2), :update)
      refute changeset.valid?
    end
  end

  describe "reaction_validate/3" do
    setup :join_dialog

    test "valid insert returns valid changeset", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash, dialog_hash: ctx.dialog_hash)

      changeset =
        Validation.reaction_validate(%DialogMessageReaction{}, to_changes(reaction), :insert)

      assert changeset.valid?
    end

    test "valid update returns valid changeset", ctx do
      {existing, next_version} = persisted_reaction_and_next(ctx, 100, 200)

      changeset = Validation.reaction_validate(existing, to_changes(next_version), :update)
      assert changeset.valid?
    end

    test "stale update returns invalid changeset", ctx do
      {existing, next_version} = persisted_reaction_and_next(ctx, 200, 100)

      changeset = Validation.reaction_validate(existing, to_changes(next_version), :update)
      refute changeset.valid?
    end
  end

  describe "receipt_validate/3" do
    test "valid insert returns valid changeset", ctx do
      receipt =
        signed_receipt(ctx.alice, ctx.alice_hash, "delivered", dialog_hash: ctx.dialog_hash)

      changeset =
        Validation.receipt_validate(%DialogMessageReceipt{}, to_changes(receipt), :insert)

      assert changeset.valid?
    end
  end

  describe "validate_reaction_insert/1 — self-reaction guard" do
    setup :join_dialog_with_alice_message

    test "rejects reaction where reactor is message author", ctx do
      reaction =
        signed_reaction(ctx.alice, ctx.alice_hash,
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      changeset = Validation.validate_reaction_insert(reaction)
      refute changeset.valid?
      assert {"cannot react to own message", _} = changeset.errors[:reactor_hash]
    end

    test "allows reaction where reactor is peer", ctx do
      reaction =
        signed_reaction(ctx.bob, ctx.bob_hash,
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      changeset = Validation.validate_reaction_insert(reaction)
      assert changeset.valid?
    end
  end

  describe "validate_receipt_insert/1 — self-receipt guard" do
    setup :join_dialog_with_alice_message

    test "rejects receipt where peer is message author", ctx do
      receipt =
        signed_receipt(ctx.alice, ctx.alice_hash, "delivered",
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      changeset = Validation.validate_receipt_insert(receipt)
      refute changeset.valid?
      assert {"cannot receipt own message", _} = changeset.errors[:peer_hash]
    end

    test "allows receipt where peer is not message author", ctx do
      receipt =
        signed_receipt(ctx.bob, ctx.bob_hash, "delivered",
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      changeset = Validation.validate_receipt_insert(receipt)
      assert changeset.valid?
    end
  end

  # --- Helpers ---

  defp to_changes(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])

  defp alice_dialog_key(ctx, owner_timestamp) do
    signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash,
      owner_timestamp: owner_timestamp
    )
  end

  defp persist_alice_dialog_key(ctx, owner_timestamp) do
    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, alice_dialog_key(ctx, owner_timestamp))
    Dialog.get_dialog_key(ctx.dialog_hash, ctx.alice_hash)
  end

  defp persisted_reaction_and_next(ctx, persisted_timestamp, next_timestamp) do
    shared = [
      reaction_hash: generate_reaction_hash(),
      message_id: DialogMessageId.generate(),
      dialog_hash: ctx.dialog_hash
    ]

    reaction =
      signed_reaction(ctx.alice, ctx.alice_hash, [owner_timestamp: persisted_timestamp] ++ shared)

    {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, reaction)

    next_version =
      signed_reaction(ctx.alice, ctx.alice_hash, [owner_timestamp: next_timestamp] ++ shared)

    {Dialog.get_reaction(reaction.reaction_hash), next_version}
  end

  defp join_dialog_with_alice_message(ctx) do
    join_dialog(ctx)
    msg = insert_alice_message(ctx)
    {:ok, message_id: msg.message_id}
  end
end

defmodule Chat.Data.DialogValidationVersioningTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.DialogDataFixtures,
    only: [alice_and_bob: 1, insert_dialog_key: 4, signed_message: 4]

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Types.DialogMessageId
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  @message_update_fields ~W(content_b64 deleted_flag refs_map_b64 parent_sign_hash owner_timestamp sign_b64 sign_hash)a

  setup :alice_and_bob

  setup ctx do
    insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
    {:ok, message_id: DialogMessageId.generate()}
  end

  describe "message_validate_with_versioning/3" do
    test "insert without conflict returns valid changeset", ctx do
      msg = alice_message(ctx, System.os_time(:millisecond))

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg), :insert)

      assert changeset.valid?
      assert changeset.action != :ignore
    end

    test "insert with existing older message sets parent_sign_hash", ctx do
      msg1 = persist_alice_message(ctx, 100)
      msg2 = alice_message(ctx, 200)

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg2), :insert)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :parent_sign_hash) == msg1.sign_hash
    end

    test "insert with existing newer message is rejected", ctx do
      persist_alice_message(ctx, 200)
      msg2 = alice_message(ctx, 100)

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg2), :insert)

      refute changeset.valid?
      assert {:owner_timestamp, {"timestamp not newer", []}} in changeset.errors
    end

    test "update with newer timestamp sets parent_sign_hash", ctx do
      msg1 = persist_alice_message(ctx, 100)
      existing = Dialog.get_message(ctx.message_id)
      msg2 = alice_message(ctx, 200)

      changeset =
        Validation.message_validate_with_versioning(existing, to_update_changes(msg2), :update)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :parent_sign_hash) == msg1.sign_hash
    end

    test "update with older timestamp is rejected", ctx do
      persist_alice_message(ctx, 200)
      existing = Dialog.get_message(ctx.message_id)
      msg2 = alice_message(ctx, 100)

      changeset =
        Validation.message_validate_with_versioning(existing, to_update_changes(msg2), :update)

      refute changeset.valid?
      assert {:owner_timestamp, {"timestamp not newer", []}} in changeset.errors
    end
  end

  # --- Helpers ---

  defp alice_message(ctx, owner_timestamp) do
    signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
      message_id: ctx.message_id,
      owner_timestamp: owner_timestamp
    )
  end

  defp persist_alice_message(ctx, owner_timestamp) do
    msg = alice_message(ctx, owner_timestamp)
    {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)
    msg
  end

  defp to_changes(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])

  defp to_update_changes(msg) do
    msg
    |> Map.from_struct()
    |> Map.take(@message_update_fields)
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
end

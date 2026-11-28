defmodule Chat.Data.DialogReactionTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.DialogDataFixtures,
    only: [
      alice_and_bob: 1,
      build_reaction: 2,
      generate_reaction_hash: 0,
      join_dialog: 1,
      signed_message: 3,
      signed_reaction: 3
    ]

  import Chat.Test.ReviewFixtures, only: [sign_with_key: 2]

  alias Chat.Data.Dialog
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup [:alice_and_bob, :join_dialog]

  describe "valid reaction — peer sync" do
    test "is persisted", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash, dialog_hash: ctx.dialog_hash)
      write_reaction(:insert, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) != nil
    end

    test "LWW — newer timestamp overwrites", ctx do
      reaction_hash =
        write_two_versions(ctx, :insert, [owner_timestamp: 100], owner_timestamp: 200)

      assert Dialog.get_reaction(reaction_hash).owner_timestamp == 200
    end

    test "LWW — older timestamp is rejected", ctx do
      reaction_hash =
        write_two_versions(ctx, :insert, [owner_timestamp: 200], owner_timestamp: 100)

      assert Dialog.get_reaction(reaction_hash).owner_timestamp == 200
    end
  end

  describe "tampered reaction — peer sync" do
    test "tampered field is not persisted", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash, dialog_hash: ctx.dialog_hash)
      write_reaction(:insert, %{reaction | type_b64: "tampered"})

      assert Dialog.get_reaction(reaction.reaction_hash) == nil
    end
  end

  describe "self-reaction — peer sync" do
    setup ctx do
      msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)

      {:ok, message_id: msg.message_id}
    end

    test "author cannot react to own message", ctx do
      reaction =
        signed_reaction(ctx.alice, ctx.alice_hash,
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      write_reaction(:insert, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) == nil
    end

    test "peer can react to author's message", ctx do
      reaction =
        signed_reaction(ctx.bob, ctx.bob_hash,
          message_id: ctx.message_id,
          dialog_hash: ctx.dialog_hash
        )

      write_reaction(:insert, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) != nil
    end
  end

  describe "signable protocol" do
    test "signable_fields excludes sign_b64 and __meta__" do
      reaction = %DialogMessageReaction{
        reaction_hash: "dmr_" <> String.duplicate("ab", 64),
        dialog_hash: "di_" <> String.duplicate("ab", 64),
        message_id: DialogMessageId.generate(),
        message_sign_hash: "dms_" <> String.duplicate("cd", 64),
        reactor_hash: "u_" <> String.duplicate("ef", 64),
        type_b64: "encrypted",
        deleted_flag: false,
        owner_timestamp: 1,
        sign_b64: "sig"
      }

      fields = Signable.signable_fields(reaction)
      refute Map.has_key?(fields, :sign_b64)
      refute Map.has_key?(fields, :__meta__)
      assert Map.has_key?(fields, :reaction_hash)
      assert Map.has_key?(fields, :reactor_hash)
    end
  end

  describe "update path — peer sync" do
    test "valid update overwrites existing", ctx do
      reaction_hash =
        write_two_versions(ctx, :update, [owner_timestamp: 100], owner_timestamp: 200)

      assert Dialog.get_reaction(reaction_hash).owner_timestamp == 200
    end

    test "stale update is rejected", ctx do
      reaction_hash =
        write_two_versions(ctx, :update, [owner_timestamp: 200], owner_timestamp: 100)

      assert Dialog.get_reaction(reaction_hash).owner_timestamp == 200
    end

    test "update for non-existing reaction is ignored", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash, dialog_hash: ctx.dialog_hash)
      write_reaction(:update, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) == nil
    end

    test "delete via update sets deleted_flag", ctx do
      reaction_hash =
        write_two_versions(ctx, :update, [owner_timestamp: 100],
          owner_timestamp: 200,
          deleted_flag: true
        )

      persisted = Dialog.get_reaction(reaction_hash)
      assert persisted.deleted_flag == true
      assert persisted.owner_timestamp == 200
    end

    test "update with invalid signature is rejected", ctx do
      stranger = User.generate_pq_identity("Bob")
      reaction_hash = generate_reaction_hash()
      shared = shared_reaction_attrs(ctx, reaction_hash)

      write_reaction(
        :insert,
        signed_reaction(ctx.alice, ctx.alice_hash, [owner_timestamp: 100] ++ shared)
      )

      ctx.alice_hash
      |> build_reaction([owner_timestamp: 200] ++ shared)
      |> sign_with_key(stranger.sign_skey)
      |> then(&write_reaction(:update, &1))

      assert Dialog.get_reaction(reaction_hash).owner_timestamp == 100
    end
  end

  # --- Helpers ---

  defp write_reaction(operation, reaction) do
    {:ok, _} = ShapeWriter.write(:dialog_message_reactions, operation, reaction)
  end

  defp write_two_versions(ctx, second_operation, first_attrs, second_attrs) do
    reaction_hash = generate_reaction_hash()
    shared = shared_reaction_attrs(ctx, reaction_hash)

    write_reaction(:insert, signed_reaction(ctx.alice, ctx.alice_hash, first_attrs ++ shared))

    write_reaction(
      second_operation,
      signed_reaction(ctx.alice, ctx.alice_hash, second_attrs ++ shared)
    )

    reaction_hash
  end

  defp shared_reaction_attrs(ctx, reaction_hash) do
    [
      reaction_hash: reaction_hash,
      message_id: DialogMessageId.generate(),
      dialog_hash: ctx.dialog_hash
    ]
  end
end

defmodule Chat.Data.DialogReactionTest do
  use ChatWeb.DataCase, async: false

  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    alice = User.generate_pq_identity("Alice")
    alice_card = insert_signed_user_card(alice)

    {:ok, alice: alice, alice_hash: alice_card.user_hash}
  end

  describe "valid reaction — peer sync" do
    test "is persisted", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, reaction)

      assert Dialog.get_reaction(reaction.reaction_hash) != nil
    end

    test "LWW — newer timestamp overwrites", ctx do
      reaction_hash = generate_reaction_hash()

      r1 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          reaction_hash: reaction_hash,
          owner_timestamp: 100
        )

      r2 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          reaction_hash: reaction_hash,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, r1)
      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, r2)

      persisted = Dialog.get_reaction(reaction_hash)
      assert persisted.owner_timestamp == 200
    end

    test "LWW — older timestamp is rejected", ctx do
      reaction_hash = generate_reaction_hash()

      r1 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          reaction_hash: reaction_hash,
          owner_timestamp: 200
        )

      r2 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          reaction_hash: reaction_hash,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, r1)
      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, r2)

      persisted = Dialog.get_reaction(reaction_hash)
      assert persisted.owner_timestamp == 200
    end
  end

  describe "tampered reaction — peer sync" do
    test "tampered field is not persisted", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash)
      tampered = %{reaction | type_b64: "tampered"}

      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, tampered)

      assert Dialog.get_reaction(reaction.reaction_hash) == nil
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

  # --- Helpers ---

  defp generate_reaction_hash do
    binary = :crypto.strong_rand_bytes(64)
    DialogMessageReactionHash.from_binary(binary)
  end

  defp build_reaction(reactor_hash, attrs \\ []) do
    %DialogMessageReaction{
      reaction_hash: Keyword.get(attrs, :reaction_hash, generate_reaction_hash()),
      dialog_hash: "di_" <> String.duplicate("ab", 64),
      message_id: DialogMessageId.generate(),
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      reactor_hash: reactor_hash,
      type_b64: :crypto.strong_rand_bytes(24),
      deleted_flag: false,
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp signed_reaction(identity, reactor_hash, attrs \\ []) do
    build_reaction(reactor_hash, attrs)
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
end

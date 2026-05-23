defmodule Chat.Data.DialogMessageTest do
  use ChatWeb.DataCase, async: false

  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageVersion
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    alice = User.generate_pq_identity("Alice")
    bob = User.generate_pq_identity("Bob")
    alice_card = insert_signed_user_card(alice)
    bob_card = insert_signed_user_card(bob)

    dialog_hash = compute_dialog_hash(alice_card.user_hash, bob_card.user_hash)

    alice_dk = signed_dialog_key(alice, dialog_hash, alice_card.user_hash, bob_card.user_hash)
    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, alice_dk)

    {:ok,
     alice: alice,
     bob: bob,
     alice_hash: alice_card.user_hash,
     bob_hash: bob_card.user_hash,
     dialog_hash: dialog_hash}
  end

  describe "valid dialog_message — peer sync" do
    test "is persisted", ctx do
      msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)

      assert Dialog.get_message(msg.message_id) != nil
    end

    test "LWW — newer timestamp overwrites", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg2)

      persisted = Dialog.get_message(message_id)
      assert persisted.owner_timestamp == 200
    end

    test "versioning — older insert is archived", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg2)

      persisted = Dialog.get_message(message_id)
      assert persisted.owner_timestamp == 200

      archived =
        Repo.get_by(DialogMessageVersion, message_id: message_id, sign_hash: msg2.sign_hash)

      assert archived != nil
      assert archived.owner_timestamp == 100
    end
  end

  describe "tampered dialog_message — peer sync" do
    test "tampered content is not persisted", ctx do
      msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
      tampered = %{msg | content_b64: "tampered"}

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, tampered)

      assert Dialog.get_message(msg.message_id) == nil
    end

    test "wrong signing key is not persisted", ctx do
      msg = build_message(ctx.dialog_hash, ctx.alice_hash) |> sign_with_key(ctx.bob.sign_skey)

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)

      assert Dialog.get_message(msg.message_id) == nil
    end
  end

  describe "signable protocol" do
    test "signable_fields excludes sign_b64, sign_hash, and __meta__" do
      msg = %DialogMessage{
        message_id: DialogMessageId.generate(),
        dialog_hash: "di_" <> String.duplicate("ab", 64),
        sender_hash: "u_" <> String.duplicate("cd", 64),
        content_b64: "content",
        deleted_flag: false,
        refs_map_b64: nil,
        parent_sign_hash: nil,
        owner_timestamp: 1,
        sign_b64: "sig",
        sign_hash: "dms_" <> String.duplicate("ef", 64)
      }

      fields = Signable.signable_fields(msg)
      refute Map.has_key?(fields, :sign_b64)
      refute Map.has_key?(fields, :sign_hash)
      refute Map.has_key?(fields, :__meta__)
      assert Map.has_key?(fields, :message_id)
      assert Map.has_key?(fields, :dialog_hash)
      assert Map.has_key?(fields, :sender_hash)
    end
  end

  describe "update path — peer sync" do
    test "valid update archives existing and replaces tip", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :update, msg2)

      persisted = Dialog.get_message(message_id)
      assert persisted.owner_timestamp == 200

      archived =
        Repo.get_by(DialogMessageVersion,
          message_id: message_id,
          sign_hash: msg1.sign_hash
        )

      assert archived != nil
      assert archived.owner_timestamp == 100
    end

    test "stale update is rejected", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :update, msg2)

      persisted = Dialog.get_message(message_id)
      assert persisted.owner_timestamp == 200
    end

    test "update for non-existing message is ignored", ctx do
      msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_messages, :update, msg)

      assert Dialog.get_message(msg.message_id) == nil
    end

    test "update with invalid signature is rejected", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)

      msg2 =
        build_message(ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )
        |> sign_with_key(ctx.bob.sign_skey)

      {:ok, _} = ShapeWriter.write(:dialog_messages, :update, msg2)

      persisted = Dialog.get_message(message_id)
      assert persisted.owner_timestamp == 100
    end
  end

  # --- Helpers ---

  defp compute_dialog_hash(hash_a, hash_b) do
    sorted = Enum.sort([hash_a, hash_b])
    binary = :crypto.hash(:sha3_512, Enum.join(sorted))
    DialogHash.from_binary(binary)
  end

  defp build_message(dialog_hash, sender_hash, attrs \\ []) do
    %DialogMessage{
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      content_b64: :crypto.strong_rand_bytes(32),
      deleted_flag: false,
      refs_map_b64: nil,
      parent_sign_hash: nil,
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp signed_message(identity, dialog_hash, sender_hash, attrs \\ []) do
    build_message(dialog_hash, sender_hash, attrs)
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

  defp signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk = %Chat.Data.Schemas.DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    sign_b64 = dk |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{dk | sign_b64: sign_b64}
  end
end

defmodule Chat.Data.DialogValidationTest do
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

    alice = User.generate_pq_identity("Alice")
    bob = User.generate_pq_identity("Bob")
    alice_card = insert_signed_user_card(alice)
    bob_card = insert_signed_user_card(bob)

    dialog_hash = compute_dialog_hash(alice_card.user_hash, bob_card.user_hash)

    {:ok,
     alice: alice,
     bob: bob,
     alice_hash: alice_card.user_hash,
     bob_hash: bob_card.user_hash,
     dialog_hash: dialog_hash}
  end

  # --- dialog_key_allowed/2 ---

  describe "dialog_key_allowed/2" do
    test "valid PoP returns :ok", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = %Operation{operation: :insert, changes: %{"sender_hash" => ctx.alice_hash}}

      assert :ok =
               Validation.dialog_key_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "invalid signature returns error", ctx do
      {challenge, _} = sign_challenge(ctx.alice)
      {_, wrong_sig} = sign_challenge(ctx.bob)

      operation = %Operation{operation: :insert, changes: %{"sender_hash" => ctx.alice_hash}}

      assert {:error, _} =
               Validation.dialog_key_allowed(operation, %{
                 challenge: challenge,
                 signature: wrong_sig
               })
    end

    test "unknown user returns error", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)
      unknown = "u_" <> String.duplicate("ff", 64)

      operation = %Operation{operation: :insert, changes: %{"sender_hash" => unknown}}

      assert {:error, _} =
               Validation.dialog_key_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "update operation extracts sender_hash from data", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = %Operation{operation: :update, data: %{"sender_hash" => ctx.alice_hash}}

      assert :ok =
               Validation.dialog_key_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end
  end

  # --- message_allowed/2 ---

  describe "message_allowed/2" do
    test "valid PoP with existing dialog_key returns :ok", ctx do
      insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = message_operation(:insert, ctx.alice_hash, ctx.dialog_hash)

      assert :ok =
               Validation.message_allowed(operation, %{challenge: challenge, signature: signature})
    end

    test "missing dialog_key returns error", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = message_operation(:insert, ctx.alice_hash, ctx.dialog_hash)

      assert {:error, "dialog_key required before posting to dialog"} =
               Validation.message_allowed(operation, %{challenge: challenge, signature: signature})
    end

    test "invalid signature returns error", ctx do
      {challenge, _} = sign_challenge(ctx.alice)
      {_, wrong_sig} = sign_challenge(ctx.bob)

      operation = message_operation(:insert, ctx.alice_hash, ctx.dialog_hash)

      assert {:error, _} =
               Validation.message_allowed(operation, %{challenge: challenge, signature: wrong_sig})
    end
  end

  # --- reaction_allowed/2 ---

  describe "reaction_allowed/2" do
    test "valid PoP with existing dialog_key returns :ok", ctx do
      insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert :ok =
               Validation.reaction_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "missing dialog_key returns error", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, "dialog_key required before posting to dialog"} =
               Validation.reaction_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "invalid signature returns error", ctx do
      {challenge, _} = sign_challenge(ctx.alice)
      {_, wrong_sig} = sign_challenge(ctx.bob)

      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, _} =
               Validation.reaction_allowed(operation, %{
                 challenge: challenge,
                 signature: wrong_sig
               })
    end

    test "rejects self-reaction — author cannot react to own message", ctx do
      msg = insert_persisted_message(ctx)
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash, message_id: msg.message_id)

      assert {:error, "cannot react to own message"} =
               Validation.reaction_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "allows peer reaction — peer can react to author's message", ctx do
      msg = insert_persisted_message(ctx)
      insert_dialog_key(ctx.bob, ctx.dialog_hash, ctx.bob_hash, ctx.alice_hash)
      {challenge, signature} = sign_challenge(ctx.bob)

      operation = reaction_operation(ctx.bob_hash, ctx.dialog_hash, message_id: msg.message_id)

      assert :ok =
               Validation.reaction_allowed(operation, %{
                 challenge: challenge,
                 signature: signature
               })
    end
  end

  # --- receipt_allowed/2 ---

  describe "receipt_allowed/2" do
    test "valid PoP returns :ok", ctx do
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = %Operation{operation: :insert, changes: %{"peer_hash" => ctx.alice_hash}}

      assert :ok =
               Validation.receipt_allowed(operation, %{challenge: challenge, signature: signature})
    end

    test "invalid signature returns error", ctx do
      {challenge, _} = sign_challenge(ctx.alice)
      {_, wrong_sig} = sign_challenge(ctx.bob)

      operation = %Operation{operation: :insert, changes: %{"peer_hash" => ctx.alice_hash}}

      assert {:error, _} =
               Validation.receipt_allowed(operation, %{challenge: challenge, signature: wrong_sig})
    end

    test "rejects self-receipt — author cannot receipt own message", ctx do
      msg = insert_persisted_message(ctx)
      {challenge, signature} = sign_challenge(ctx.alice)

      operation = %Operation{
        operation: :insert,
        changes: %{"peer_hash" => ctx.alice_hash, "message_id" => msg.message_id}
      }

      assert {:error, "cannot receipt own message"} =
               Validation.receipt_allowed(operation, %{challenge: challenge, signature: signature})
    end

    test "allows peer receipt — peer can receipt author's message", ctx do
      msg = insert_persisted_message(ctx)
      {challenge, signature} = sign_challenge(ctx.bob)

      operation = %Operation{
        operation: :insert,
        changes: %{"peer_hash" => ctx.bob_hash, "message_id" => msg.message_id}
      }

      assert :ok =
               Validation.receipt_allowed(operation, %{challenge: challenge, signature: signature})
    end
  end

  # --- dialog_key_validate/3 ---

  describe "dialog_key_validate/3" do
    test "valid insert returns valid changeset", ctx do
      dk = signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)

      changeset = Validation.dialog_key_validate(%DialogKey{}, to_changes(dk), :insert)
      assert changeset.valid?
    end

    test "tampered insert returns invalid changeset", ctx do
      dk = signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      changes = dk |> to_changes() |> Map.put(:peer_hash, ctx.alice_hash)

      changeset = Validation.dialog_key_validate(%DialogKey{}, changes, :insert)
      refute changeset.valid?
    end

    test "valid update returns valid changeset", ctx do
      dk1 =
        signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)
      existing = Dialog.get_dialog_key(ctx.dialog_hash, ctx.alice_hash)

      dk2 =
        signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash,
          owner_timestamp: 200
        )

      changeset = Validation.dialog_key_validate(existing, to_changes(dk2), :update)
      assert changeset.valid?
    end

    test "stale update returns invalid changeset", ctx do
      dk1 =
        signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)
      existing = Dialog.get_dialog_key(ctx.dialog_hash, ctx.alice_hash)

      dk2 =
        signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash,
          owner_timestamp: 100
        )

      changeset = Validation.dialog_key_validate(existing, to_changes(dk2), :update)
      refute changeset.valid?
    end
  end

  # --- message_validate_with_versioning/3 ---

  describe "message_validate_with_versioning/3" do
    setup ctx do
      dk = signed_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)
      :ok
    end

    test "insert without conflict returns valid changeset", ctx do
      msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg), :insert)

      assert changeset.valid?
      assert changeset.action != :ignore
    end

    test "insert with existing older message sets parent_sign_hash", ctx do
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

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg2), :insert)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :parent_sign_hash) == msg1.sign_hash
    end

    test "insert with existing newer message sets action to ignore", ctx do
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

      changeset =
        Validation.message_validate_with_versioning(%DialogMessage{}, to_changes(msg2), :insert)

      assert changeset.action == :ignore
    end

    test "update with newer timestamp sets parent_sign_hash", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)
      existing = Dialog.get_message(message_id)

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      changeset =
        Validation.message_validate_with_versioning(existing, to_update_changes(msg2), :update)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :parent_sign_hash) == msg1.sign_hash
    end

    test "update with older timestamp sets action to ignore", ctx do
      message_id = DialogMessageId.generate()

      msg1 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 200
        )

      {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg1)
      existing = Dialog.get_message(message_id)

      msg2 =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: message_id,
          owner_timestamp: 100
        )

      changeset =
        Validation.message_validate_with_versioning(existing, to_update_changes(msg2), :update)

      assert changeset.action == :ignore
    end
  end

  # --- reaction_validate/3 ---

  describe "reaction_validate/3" do
    test "valid insert returns valid changeset", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash)

      changeset =
        Validation.reaction_validate(%DialogMessageReaction{}, to_changes(reaction), :insert)

      assert changeset.valid?
    end

    test "valid update returns valid changeset", ctx do
      message_id = DialogMessageId.generate()

      reaction =
        signed_reaction(ctx.alice, ctx.alice_hash, message_id: message_id, owner_timestamp: 100)

      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, reaction)
      existing = Dialog.get_reaction(reaction.reaction_hash)

      reaction2 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          message_id: message_id,
          reaction_hash: reaction.reaction_hash,
          owner_timestamp: 200
        )

      changeset = Validation.reaction_validate(existing, to_changes(reaction2), :update)
      assert changeset.valid?
    end

    test "stale update returns invalid changeset", ctx do
      message_id = DialogMessageId.generate()

      reaction =
        signed_reaction(ctx.alice, ctx.alice_hash, message_id: message_id, owner_timestamp: 200)

      {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, reaction)
      existing = Dialog.get_reaction(reaction.reaction_hash)

      reaction2 =
        signed_reaction(ctx.alice, ctx.alice_hash,
          message_id: message_id,
          reaction_hash: reaction.reaction_hash,
          owner_timestamp: 100
        )

      changeset = Validation.reaction_validate(existing, to_changes(reaction2), :update)
      refute changeset.valid?
    end
  end

  # --- receipt_validate/3 ---

  describe "receipt_validate/3" do
    test "valid insert returns valid changeset", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "delivered")

      changeset =
        Validation.receipt_validate(%DialogMessageReceipt{}, to_changes(receipt), :insert)

      assert changeset.valid?
    end
  end

  # --- self-action peer sync validation ---

  describe "validate_reaction_insert/1 — self-reaction guard" do
    setup ctx do
      msg = insert_persisted_message(ctx)
      {:ok, message_id: msg.message_id}
    end

    test "rejects reaction where reactor is message author", ctx do
      reaction = signed_reaction(ctx.alice, ctx.alice_hash, message_id: ctx.message_id)

      changeset = Validation.validate_reaction_insert(reaction)
      refute changeset.valid?
      assert {"cannot react to own message", _} = changeset.errors[:reactor_hash]
    end

    test "allows reaction where reactor is peer", ctx do
      reaction = signed_reaction(ctx.bob, ctx.bob_hash, message_id: ctx.message_id)

      changeset = Validation.validate_reaction_insert(reaction)
      assert changeset.valid?
    end
  end

  describe "validate_receipt_insert/1 — self-receipt guard" do
    setup ctx do
      msg = insert_persisted_message(ctx)
      {:ok, message_id: msg.message_id}
    end

    test "rejects receipt where peer is message author", ctx do
      receipt = signed_receipt(ctx.alice, ctx.alice_hash, "delivered", message_id: ctx.message_id)

      changeset = Validation.validate_receipt_insert(receipt)
      refute changeset.valid?
      assert {"cannot receipt own message", _} = changeset.errors[:peer_hash]
    end

    test "allows receipt where peer is not message author", ctx do
      receipt = signed_receipt(ctx.bob, ctx.bob_hash, "delivered", message_id: ctx.message_id)

      changeset = Validation.validate_receipt_insert(receipt)
      assert changeset.valid?
    end
  end

  # --- Helpers ---

  @message_update_fields ~w(content_b64 deleted_flag refs_map_b64 parent_sign_hash owner_timestamp sign_b64 sign_hash)a

  defp to_changes(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])

  defp to_update_changes(msg) do
    msg
    |> Map.from_struct()
    |> Map.take(@message_update_fields)
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp compute_dialog_hash(hash_a, hash_b) do
    sorted = Enum.sort([hash_a, hash_b])
    binary = :crypto.hash(:sha3_512, Enum.join(sorted))
    DialogHash.from_binary(binary)
  end

  defp sign_challenge(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    signature = EnigmaPq.sign(challenge, identity.sign_skey)
    {challenge, signature}
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp sign_message_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash, attrs \\ []) do
    %DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond)),
      deleted_flag: false
    }
    |> sign_with_key(identity.sign_skey)
  end

  defp signed_message(identity, dialog_hash, sender_hash, attrs \\ []) do
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
    |> sign_message_with_key(identity.sign_skey)
  end

  defp signed_reaction(identity, reactor_hash, attrs \\ []) do
    %DialogMessageReaction{
      reaction_hash: Keyword.get(attrs, :reaction_hash, generate_reaction_hash()),
      dialog_hash: "di_" <> String.duplicate("ab", 64),
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      reactor_hash: reactor_hash,
      type_b64: :crypto.strong_rand_bytes(24),
      deleted_flag: false,
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }
    |> sign_with_key(identity.sign_skey)
  end

  defp signed_receipt(identity, peer_hash, type, attrs \\ []) do
    %DialogMessageReceipt{
      receipt_hash: Keyword.get(attrs, :receipt_hash, generate_receipt_hash()),
      dialog_hash: "di_" <> String.duplicate("ab", 64),
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      peer_hash: peer_hash,
      type: type,
      message_sign_hash: "dms_" <> String.duplicate("cd", 64),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }
    |> sign_with_key(identity.sign_skey)
  end

  defp generate_reaction_hash do
    :crypto.strong_rand_bytes(64) |> DialogMessageReactionHash.from_binary()
  end

  defp generate_receipt_hash do
    :crypto.strong_rand_bytes(64) |> DialogMessageReceiptHash.from_binary()
  end

  defp insert_signed_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp insert_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk = signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash)
    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)
    dk
  end

  defp insert_persisted_message(ctx) do
    insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
    msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
    {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)
    msg
  end

  defp message_operation(:insert, sender_hash, dialog_hash) do
    %Operation{
      operation: :insert,
      changes: %{"sender_hash" => sender_hash, "dialog_hash" => dialog_hash}
    }
  end

  defp reaction_operation(reactor_hash, dialog_hash, attrs \\ []) do
    changes =
      %{"reactor_hash" => reactor_hash, "dialog_hash" => dialog_hash}
      |> maybe_put("message_id", Keyword.get(attrs, :message_id))

    %Operation{operation: :insert, changes: changes}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule Chat.Data.DialogValidationTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.DialogDataFixtures,
    only: [alice_and_bob: 1, insert_alice_message: 1, insert_dialog_key: 4, join_dialog: 1]

  alias Chat.Data.Dialog.Validation
  alias Phoenix.Sync.Writer.Operation

  setup :alice_and_bob

  describe "dialog_key_allowed/2" do
    test "valid PoP returns :ok", ctx do
      operation = %Operation{operation: :insert, changes: %{"sender_hash" => ctx.alice_hash}}

      assert :ok = Validation.dialog_key_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "invalid signature returns error", ctx do
      operation = %Operation{operation: :insert, changes: %{"sender_hash" => ctx.alice_hash}}

      assert {:error, _} =
               Validation.dialog_key_allowed(operation, forged_proof(ctx.alice, ctx.bob))
    end

    test "unknown user returns error", ctx do
      unknown = "u_" <> String.duplicate("ff", 64)
      operation = %Operation{operation: :insert, changes: %{"sender_hash" => unknown}}

      assert {:error, _} =
               Validation.dialog_key_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "update operation extracts sender_hash from data", ctx do
      operation = %Operation{operation: :update, data: %{"sender_hash" => ctx.alice_hash}}

      assert :ok = Validation.dialog_key_allowed(operation, proof_of_possession(ctx.alice))
    end
  end

  describe "message_allowed/2" do
    test "valid PoP with existing dialog_key returns :ok", ctx do
      insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      operation = message_operation(ctx.alice_hash, ctx.dialog_hash)

      assert :ok = Validation.message_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "missing dialog_key returns error", ctx do
      operation = message_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, "dialog_key required before posting to dialog"} =
               Validation.message_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "invalid signature returns error", ctx do
      operation = message_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, _} = Validation.message_allowed(operation, forged_proof(ctx.alice, ctx.bob))
    end
  end

  describe "reaction_allowed/2" do
    test "valid PoP with existing dialog_key returns :ok", ctx do
      insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert :ok = Validation.reaction_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "missing dialog_key returns error", ctx do
      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, "not a dialog participant"} =
               Validation.reaction_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "invalid signature returns error", ctx do
      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, _} =
               Validation.reaction_allowed(operation, forged_proof(ctx.alice, ctx.bob))
    end

    test "rejects self-reaction — author cannot react to own message", ctx do
      msg = insert_alice_message(ctx)
      operation = reaction_operation(ctx.alice_hash, ctx.dialog_hash, msg.message_id)

      assert {:error, "cannot react to own message"} =
               Validation.reaction_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "allows peer reaction — peer can react to author's message", ctx do
      msg = insert_alice_message(ctx)
      insert_dialog_key(ctx.bob, ctx.dialog_hash, ctx.bob_hash, ctx.alice_hash)
      operation = reaction_operation(ctx.bob_hash, ctx.dialog_hash, msg.message_id)

      assert :ok = Validation.reaction_allowed(operation, proof_of_possession(ctx.bob))
    end
  end

  describe "receipt_allowed/2" do
    setup :join_dialog

    test "valid PoP returns :ok", ctx do
      operation = receipt_operation(ctx.alice_hash, ctx.dialog_hash)

      assert :ok = Validation.receipt_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "invalid signature returns error", ctx do
      operation = receipt_operation(ctx.alice_hash, ctx.dialog_hash)

      assert {:error, _} = Validation.receipt_allowed(operation, forged_proof(ctx.alice, ctx.bob))
    end

    test "rejects self-receipt — author cannot receipt own message", ctx do
      msg = insert_alice_message(ctx)
      operation = receipt_operation(ctx.alice_hash, ctx.dialog_hash, msg.message_id)

      assert {:error, "cannot receipt own message"} =
               Validation.receipt_allowed(operation, proof_of_possession(ctx.alice))
    end

    test "allows peer receipt — peer can receipt author's message", ctx do
      msg = insert_alice_message(ctx)
      operation = receipt_operation(ctx.bob_hash, ctx.dialog_hash, msg.message_id)

      assert :ok = Validation.receipt_allowed(operation, proof_of_possession(ctx.bob))
    end
  end

  # --- Helpers ---

  defp proof_of_possession(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    %{challenge: challenge, signature: EnigmaPq.sign(challenge, identity.sign_skey)}
  end

  defp forged_proof(identity, forger) do
    %{
      challenge: proof_of_possession(identity).challenge,
      signature: proof_of_possession(forger).signature
    }
  end

  defp message_operation(sender_hash, dialog_hash) do
    %Operation{
      operation: :insert,
      changes: %{"sender_hash" => sender_hash, "dialog_hash" => dialog_hash}
    }
  end

  defp reaction_operation(reactor_hash, dialog_hash, message_id \\ nil) do
    changes =
      %{"reactor_hash" => reactor_hash, "dialog_hash" => dialog_hash}
      |> maybe_put("message_id", message_id)

    %Operation{operation: :insert, changes: changes}
  end

  defp receipt_operation(peer_hash, dialog_hash, message_id \\ nil) do
    changes =
      %{"peer_hash" => peer_hash, "dialog_hash" => dialog_hash}
      |> maybe_put("message_id", message_id)

    %Operation{operation: :insert, changes: changes}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule ChatWeb.ElectricControllerDialogMessageReactionTest do
  @moduledoc """
  Reproduces (with synthetic identities/signatures) a captured production
  ingest_each request that bundles a new outgoing message together with the
  retraction of two earlier reactions in one HTTP call.
  """

  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User, as: UserData
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup %{conn: conn} do
    alice = UserData.generate_pq_identity("Alice")
    bob = UserData.generate_pq_identity("Bob")

    alice_card = insert_signed_user_card(alice)
    bob_card = insert_signed_user_card(bob)

    dialog_hash = compute_dialog_hash(alice_card.user_hash, bob_card.user_hash)

    {:ok, _} =
      ShapeWriter.write(
        :dialog_keys,
        :insert,
        signed_dialog_key(alice, dialog_hash, alice_card.user_hash, bob_card.user_hash)
      )

    {:ok, _} =
      ShapeWriter.write(
        :dialog_keys,
        :insert,
        signed_dialog_key(bob, dialog_hash, bob_card.user_hash, alice_card.user_hash)
      )

    %{
      conn: conn,
      alice: alice,
      bob: bob,
      alice_hash: alice_card.user_hash,
      bob_hash: bob_card.user_hash,
      dialog_hash: dialog_hash
    }
  end

  describe "batched ingest_each: new message plus reaction retractions in one client flush" do
    test "sends a message and retracts two earlier reactions in a single request", ctx do
      msg1 = insert_persisted_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
      msg2 = insert_persisted_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)

      reaction1 = insert_persisted_reaction(ctx, msg1)
      reaction2 = insert_persisted_reaction(ctx, msg2)

      new_message = signed_message(ctx.bob, ctx.dialog_hash, ctx.bob_hash)
      retraction1 = retracted(ctx.bob, reaction1)
      retraction2 = retracted(ctx.bob, reaction2)

      payload = %{
        "mutations" => [
          message_insert_mutation(new_message, ctx.dialog_hash, ctx.bob_hash),
          reaction_update_mutation(reaction1, retraction1),
          reaction_update_mutation(reaction2, retraction2)
        ]
      }

      conn = post_ingest_each(ctx.conn, payload, ctx.bob.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"results" => results} = Jason.decode!(conn.resp_body)
      assert length(results) == 3
      assert Enum.all?(results, &(&1["status"] == "ok"))
      assert Enum.all?(results, &is_integer(&1["txid"]))

      assert Dialog.get_message(new_message.message_id).content_b64 == new_message.content_b64
      assert Dialog.get_reaction(reaction1.reaction_hash).deleted_flag == true
      assert Dialog.get_reaction(reaction2.reaction_hash).deleted_flag == true
    end
  end

  # --- Helpers ---

  defp insert_persisted_message(identity, dialog_hash, sender_hash) do
    msg = signed_message(identity, dialog_hash, sender_hash)
    {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)
    msg
  end

  defp signed_message(identity, dialog_hash, sender_hash, attrs \\ []) do
    msg = %DialogMessage{
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      content_b64: Keyword.get(attrs, :content_b64, :crypto.strong_rand_bytes(32)),
      deleted_flag: Keyword.get(attrs, :deleted_flag, false),
      refs_map_b64: Keyword.get(attrs, :refs_map_b64, :crypto.strong_rand_bytes(24)),
      parent_sign_hash: Keyword.get(attrs, :parent_sign_hash, nil),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }

    sign_b64 = msg |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    %{msg | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp insert_persisted_reaction(ctx, message) do
    reaction = %DialogMessageReaction{
      reaction_hash: DialogMessageReactionHash.from_binary(:crypto.strong_rand_bytes(64)),
      dialog_hash: ctx.dialog_hash,
      message_id: message.message_id,
      message_sign_hash: message.sign_hash,
      reactor_hash: ctx.bob_hash,
      type_b64: :crypto.strong_rand_bytes(4),
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = reaction |> Integrity.signature_payload() |> EnigmaPq.sign(ctx.bob.sign_skey)
    reaction = %{reaction | sign_b64: sign_b64}

    {:ok, _} = ShapeWriter.write(:dialog_message_reactions, :insert, reaction)
    reaction
  end

  defp retracted(identity, reaction) do
    updated = %{reaction | deleted_flag: true, owner_timestamp: reaction.owner_timestamp + 1}
    sign_b64 = updated |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{updated | sign_b64: sign_b64}
  end

  defp compute_dialog_hash(hash_a, hash_b) do
    [hash_a, hash_b]
    |> Enum.sort()
    |> Enum.join()
    |> then(&:crypto.hash(:sha3_512, &1))
    |> DialogHash.from_binary()
  end

  defp signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk = %DialogKey{
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

  defp insert_signed_user_card(identity) do
    card =
      identity
      |> UserData.extract_pq_card()
      |> then(fn card ->
        sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
        %{card | sign_b64: sign_b64}
      end)

    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp message_insert_mutation(msg, dialog_hash, sender_hash) do
    %{
      "type" => "insert",
      "modified" => %{
        "message_id" => msg.message_id,
        "dialog_hash" => dialog_hash,
        "sender_hash" => sender_hash,
        "content_b64" => to_base64(msg.content_b64),
        "deleted_flag" => false,
        "refs_map_b64" => maybe_base64(msg.refs_map_b64),
        "parent_sign_hash" => nil,
        "owner_timestamp" => msg.owner_timestamp,
        "sign_b64" => to_base64(msg.sign_b64),
        "sign_hash" => msg.sign_hash
      },
      "syncMetadata" => %{"relation" => "dialog_messages"}
    }
  end

  defp reaction_update_mutation(original, updated) do
    %{
      "type" => "update",
      "original" => %{
        "reaction_hash" => original.reaction_hash,
        "reactor_hash" => original.reactor_hash,
        "dialog_hash" => original.dialog_hash,
        "message_id" => original.message_id
      },
      "changes" => %{
        "type_b64" => to_base64(updated.type_b64),
        "deleted_flag" => updated.deleted_flag,
        "owner_timestamp" => updated.owner_timestamp,
        "sign_b64" => to_base64(updated.sign_b64)
      },
      "syncMetadata" => %{"relation" => "dialog_message_reactions"}
    }
  end

  defp to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  defp maybe_base64(nil), do: nil
  defp maybe_base64(bin), do: to_base64(bin)

  defp post_ingest_each(conn, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    signature_b64 =
      challenge
      |> EnigmaPq.sign(sign_skey)
      |> Base.encode64(padding: false)

    payload =
      Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest_each", Jason.encode!(payload))
  end
end

defmodule ChatWeb.ElectricControllerDialogMessageTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageVersion
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User, as: UserData
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  setup %{conn: conn} do
    alice = UserData.generate_pq_identity("Alice")
    bob = UserData.generate_pq_identity("Bob")

    alice_card = insert_signed_user_card(alice)
    bob_card = insert_signed_user_card(bob)

    dialog_hash = compute_dialog_hash(alice_card.user_hash, bob_card.user_hash)

    dk = signed_dialog_key(alice, dialog_hash, alice_card.user_hash, bob_card.user_hash)
    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)

    %{
      conn: conn,
      alice: alice,
      bob: bob,
      alice_hash: alice_card.user_hash,
      bob_hash: bob_card.user_hash,
      dialog_hash: dialog_hash
    }
  end

  describe "message edit via HTTP ingest" do
    test "update mutation edits message and archives old version", ctx do
      msg = insert_persisted_message(ctx)
      new_content = :crypto.strong_rand_bytes(32)

      edit =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: msg.message_id,
          content_b64: new_content,
          parent_sign_hash: msg.sign_hash,
          owner_timestamp: msg.owner_timestamp + 1
        )

      payload = message_update_payload(msg.message_id, ctx.alice_hash, ctx.dialog_hash, edit)

      conn = post_ingest(ctx.conn, payload, ctx.alice.sign_skey)

      assert conn.status == 200, conn.resp_body

      tip = Dialog.get_message(msg.message_id)
      assert tip.content_b64 == new_content
      assert tip.parent_sign_hash == msg.sign_hash
      assert tip.owner_timestamp == msg.owner_timestamp + 1

      archived =
        Repo.get_by(DialogMessageVersion, message_id: msg.message_id, sign_hash: msg.sign_hash)

      assert archived != nil
      assert archived.owner_timestamp == msg.owner_timestamp
    end

    @tag :skip
    test "stale edit does not overwrite newer tip", ctx do
      msg = insert_persisted_message(ctx, owner_timestamp: 200)

      edit =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: msg.message_id,
          parent_sign_hash: msg.sign_hash,
          owner_timestamp: 100
        )

      payload = message_update_payload(msg.message_id, ctx.alice_hash, ctx.dialog_hash, edit)

      post_ingest(ctx.conn, payload, ctx.alice.sign_skey)

      tip = Dialog.get_message(msg.message_id)
      assert tip.owner_timestamp == 200
    end

    test "edit by wrong user is rejected", ctx do
      msg = insert_persisted_message(ctx)

      dk = signed_dialog_key(ctx.bob, ctx.dialog_hash, ctx.bob_hash, ctx.alice_hash)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)

      edit =
        signed_message(ctx.bob, ctx.dialog_hash, ctx.bob_hash,
          message_id: msg.message_id,
          parent_sign_hash: msg.sign_hash,
          owner_timestamp: msg.owner_timestamp + 1
        )

      payload = message_update_payload(msg.message_id, ctx.bob_hash, ctx.dialog_hash, edit)

      conn = post_ingest(ctx.conn, payload, ctx.bob.sign_skey)

      assert conn.status in [400, 422]

      tip = Dialog.get_message(msg.message_id)
      assert tip.owner_timestamp == msg.owner_timestamp
    end
  end

  describe "message delete via HTTP ingest" do
    test "update mutation with deleted_flag deletes message", ctx do
      msg = insert_persisted_message(ctx)

      delete =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: msg.message_id,
          content_b64: nil,
          deleted_flag: true,
          parent_sign_hash: msg.sign_hash,
          owner_timestamp: msg.owner_timestamp + 1
        )

      payload = message_update_payload(msg.message_id, ctx.alice_hash, ctx.dialog_hash, delete)

      conn = post_ingest(ctx.conn, payload, ctx.alice.sign_skey)

      assert conn.status == 200, conn.resp_body

      tip = Dialog.get_message(msg.message_id)
      assert tip.deleted_flag == true
      assert is_nil(tip.content_b64)
      assert tip.parent_sign_hash == msg.sign_hash

      archived =
        Repo.get_by(DialogMessageVersion, message_id: msg.message_id, sign_hash: msg.sign_hash)

      assert archived != nil
      assert archived.deleted_flag == false
    end

    test "full HTTP round-trip: insert then delete", ctx do
      msg = insert_message_via_http(ctx)

      delete =
        signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
          message_id: msg.message_id,
          content_b64: nil,
          deleted_flag: true,
          parent_sign_hash: msg.sign_hash,
          owner_timestamp: msg.owner_timestamp + 1
        )

      payload = message_update_payload(msg.message_id, ctx.alice_hash, ctx.dialog_hash, delete)

      conn = post_ingest(ctx.conn, payload, ctx.alice.sign_skey)

      assert conn.status == 200, conn.resp_body

      tip = Dialog.get_message(msg.message_id)
      assert tip.deleted_flag == true
    end
  end

  # --- "message delete" helpers ---

  defp insert_message_via_http(ctx) do
    msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "message_id" => msg.message_id,
            "dialog_hash" => ctx.dialog_hash,
            "sender_hash" => ctx.alice_hash,
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
      ]
    }

    conn = post_ingest(ctx.conn, payload, ctx.alice.sign_skey)
    assert conn.status == 200, "Insert failed: #{conn.resp_body}"
    msg
  end

  # --- Helpers ---

  defp message_update_payload(message_id, sender_hash, dialog_hash, edit) do
    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "message_id" => message_id,
            "sender_hash" => sender_hash,
            "dialog_hash" => dialog_hash
          },
          "changes" => %{
            "content_b64" => encode_content(edit.content_b64),
            "deleted_flag" => edit.deleted_flag,
            "refs_map_b64" => maybe_base64(edit.refs_map_b64),
            "parent_sign_hash" => edit.parent_sign_hash,
            "owner_timestamp" => edit.owner_timestamp,
            "sign_b64" => to_base64(edit.sign_b64),
            "sign_hash" => edit.sign_hash
          },
          "syncMetadata" => %{"relation" => "dialog_messages"}
        }
      ]
    }
  end

  defp insert_persisted_message(ctx, attrs \\ []) do
    msg =
      signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash,
        owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
      )

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

  defp to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  defp maybe_base64(nil), do: nil
  defp maybe_base64(bin), do: to_base64(bin)

  defp encode_content(nil), do: ""
  defp encode_content(bin), do: to_base64(bin)

  defp post_ingest(conn, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    signature_b64 =
      challenge
      |> EnigmaPq.sign(sign_skey)
      |> Base.encode64(padding: false)

    payload =
      Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end
end

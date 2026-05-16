defmodule ChatWeb.ElectricControllerIngestEachTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.User, as: UserData

  setup %{conn: conn} do
    identity = UserData.generate_pq_identity("Alice")
    card = UserData.extract_pq_card(identity)
    %{conn: conn, identity: identity, card: card}
  end

  describe "ingest_each sunny day" do
    test "single valid mutation returns 200 with one result", ctx do
      payload = mutations_payload([user_card_insert(ctx.card)])

      conn = post_ingest_each(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 200

      assert %{"results" => [%{"index" => 0, "status" => "ok", "txid" => txid}]} =
               Jason.decode!(conn.resp_body)

      assert is_integer(txid)
    end

    test "insert + update of same card returns 200 with two results", ctx do
      insert_mutation = user_card_insert(ctx.card)
      update_mutation = user_card_update(ctx.card, ctx.identity.sign_skey, "Alice Updated")

      payload = mutations_payload([insert_mutation, update_mutation])

      conn = post_ingest_each(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 200
      assert %{"results" => results} = Jason.decode!(conn.resp_body)
      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "ok"))
      assert Enum.all?(results, &is_integer(&1["txid"]))
    end

    defp user_card_update(card, sign_skey, new_name) do
      updated =
        signed_user_card(card, sign_skey, %{
          name: new_name,
          owner_timestamp: card.owner_timestamp + 1
        })

      %{
        "type" => "update",
        "original" => %{"user_hash" => card.user_hash},
        "changes" => %{
          "name" => updated.name,
          "owner_timestamp" => updated.owner_timestamp,
          "sign_b64" => to_base64(updated.sign_b64)
        },
        "syncMetadata" => %{"relation" => "user_cards"}
      }
    end

    defp signed_user_card(card, sign_skey, attrs) do
      updated_card = struct(card, attrs)
      sign_b64 = updated_card |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
      %{updated_card | sign_b64: sign_b64}
    end
  end

  describe "ingest_each partial failure" do
    test "one valid + one invalid returns 422 with mixed results", ctx do
      valid_mutation = user_card_insert(ctx.card)
      invalid_mutation = card_insert_without_name(ctx.card)

      payload = mutations_payload([valid_mutation, invalid_mutation])

      conn = post_ingest_each(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 422
      assert %{"results" => [first, second]} = Jason.decode!(conn.resp_body)
      assert first["status"] == "ok"
      assert is_integer(first["txid"])
      assert second["status"] == "error"
      assert second["index"] == 1
    end

    test "decode error on one mutation does not block others", ctx do
      valid_mutation = user_card_insert(ctx.card)
      bad_mutation = card_insert_with_bad_base64(ctx.card)

      payload = mutations_payload([valid_mutation, bad_mutation])

      conn = post_ingest_each(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 422
      assert %{"results" => [first, second]} = Jason.decode!(conn.resp_body)
      assert first["status"] == "ok"
      assert second["status"] == "error"
    end

    defp card_insert_with_bad_base64(card) do
      card
      |> user_card_modified()
      |> Map.put("sign_pkey", "not-base64")
      |> user_card_insert_raw()
    end
  end

  describe "ingest_each all fail" do
    test "two invalid mutations return 422 with all errors", ctx do
      payload =
        mutations_payload([
          card_insert_without_name(ctx.card),
          card_insert_without_name(ctx.card)
        ])

      conn = post_ingest_each(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 422
      assert %{"results" => results} = Jason.decode!(conn.resp_body)
      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "error"))
    end
  end

  describe "ingest_each request-level errors" do
    test "missing PoP auth returns 401", ctx do
      payload = mutations_payload([user_card_insert(ctx.card)])

      conn =
        ctx.conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest_each", Jason.encode!(payload))

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end

    test "invalid payload returns 400", ctx do
      conn = post(ctx.conn, "/electric/v1/ingest_each", %{})

      assert conn.status == 400
      assert conn.resp_body == "invalid_payload"
    end
  end

  # -- Shared helpers --

  defp mutations_payload(mutations) do
    %{"mutations" => mutations}
  end

  defp user_card_insert(card) do
    %{
      "type" => "insert",
      "modified" => user_card_modified(card),
      "syncMetadata" => %{"relation" => "user_cards"}
    }
  end

  defp user_card_insert_raw(modified) do
    %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "user_cards"}
    }
  end

  defp card_insert_without_name(card) do
    card
    |> user_card_modified()
    |> Map.delete("name")
    |> user_card_insert_raw()
  end

  defp user_card_modified(card) do
    %{
      "user_hash" => card.user_hash,
      "sign_pkey" => to_base64(card.sign_pkey),
      "contact_pkey" => to_base64(card.contact_pkey),
      "contact_cert" => to_base64(card.contact_cert),
      "crypt_pkey" => to_base64(card.crypt_pkey),
      "crypt_cert" => to_base64(card.crypt_cert),
      "name" => card.name,
      "deleted_flag" => card.deleted_flag,
      "owner_timestamp" => card.owner_timestamp,
      "sign_b64" => to_base64(card.sign_b64)
    }
  end

  defp to_base64(bin), do: Base.encode64(bin, padding: false)

  defp post_ingest_each(conn, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    signature_b64 =
      challenge
      |> EnigmaPq.sign(sign_skey)
      |> Base.encode64(padding: false)

    payload =
      payload
      |> Map.put("auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest_each", Jason.encode!(payload))
  end
end

defmodule ChatWeb.ElectricControllerTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User, as: UserData
  alias Chat.Repo

  setup do
    identity = UserData.generate_pq_identity("Bob")
    card = UserData.extract_pq_card(identity)
    %{identity: identity, card: card}
  end

  describe "sunny day scenarios" do
    test "POST /electric/v1/ingest with valid mutations returns txid",
         %{conn: conn, identity: identity, card: card} do
      payload = user_card_payload(user_card_modified(card))

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with valid update mutation returns txid",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      update_payload = update_name_payload(card, identity.sign_skey, "Bob Updated")
      update_conn = post_ingest(conn, update_payload, identity.sign_skey)

      assert update_conn.status == 200, update_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(update_conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with valid delete mutation soft-deletes card",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      delete_payload = delete_card_payload(card, identity.sign_skey)
      delete_conn = post_ingest(conn, delete_payload, identity.sign_skey)

      assert delete_conn.status == 200, delete_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(delete_conn.resp_body)
      assert is_integer(txid)

      deleted_card = Repo.get(UserCard, card.user_hash)
      assert deleted_card != nil
      assert deleted_card.deleted_flag == true
    end
  end

  describe "error checking scenarios" do
    test "POST /electric/v1/ingest with invalid payload returns 400", %{conn: conn} do
      conn = post(conn, "/electric/v1/ingest", %{})

      assert conn.status == 400
      assert conn.resp_body == "invalid_payload"
    end

    test "POST /electric/v1/ingest with missing name returns 422 and details",
         %{conn: conn, identity: identity, card: card} do
      payload =
        card
        |> user_card_modified()
        |> Map.delete("name")
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 422

      assert %{"error" => "validation_failed", "details" => %{"name" => _}} =
               Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with duplicate user_hash returns conflict with ownership",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      payload = user_card_payload(user_card_modified(card))
      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 409
      assert %{"status" => "exists", "conflicted" => false} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with invalid pub_key returns 400",
         %{conn: conn, identity: identity, card: card} do
      payload =
        card
        |> user_card_modified()
        |> Map.put("sign_pkey", "not-base64")
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "invalid_base64_field"
    end

    test "POST /electric/v1/ingest with tampered user_hash returns 422",
         %{conn: conn, identity: identity, card: card} do
      # u_ prefix + 128 hex chars to match expected format
      tampered_hash = "u_" <> Base.encode16(:crypto.strong_rand_bytes(64), case: :lower)

      payload =
        card
        |> user_card_modified()
        |> Map.put("user_hash", tampered_hash)
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert_invalid_signature(conn)
    end

    test "POST /electric/v1/ingest with invalid crypt_cert returns 422",
         %{conn: conn, identity: identity, card: card} do
      payload = payload_with_tampered_cert(card, :crypt_cert)

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert_invalid_signature(conn)
    end

    test "POST /electric/v1/ingest with invalid contact_cert returns 422",
         %{conn: conn, identity: identity, card: card} do
      payload = payload_with_tampered_cert(card, :contact_cert)

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert_invalid_signature(conn)
    end

    test "POST /electric/v1/ingest update with invalid PoP returns 400",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      other_identity = UserData.generate_pq_identity("Alice")
      update_payload = update_name_payload(card, other_identity.sign_skey, "Hacked Name")
      update_conn = post_ingest(conn, update_payload, other_identity.sign_skey)

      assert update_conn.status == 400
      assert update_conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest update without PoP returns 401",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      update_payload = update_name_payload(card, identity.sign_skey, "Hacked Name")
      conn = post_without_auth(conn, update_payload)

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest delete with invalid PoP returns 400",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      other_identity = UserData.generate_pq_identity("Alice")
      delete_payload = delete_card_payload(card, other_identity.sign_skey)
      delete_conn = post_ingest(conn, delete_payload, other_identity.sign_skey)

      assert delete_conn.status == 400
      assert delete_conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest delete without PoP returns 401",
         %{conn: conn, identity: identity, card: card} do
      insert_card(conn, card, identity.sign_skey)

      delete_payload = delete_card_payload(card, identity.sign_skey)
      conn = post_without_auth(conn, delete_payload)

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end
  end

  # Payload builders

  defp user_card_payload(modified) do
    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => modified,
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
  end

  defp update_name_payload(card, sign_skey, new_name) do
    updated =
      signed_user_card(card, sign_skey, %{
        name: new_name,
        owner_timestamp: card.owner_timestamp + 1
      })

    %{
      "mutations" => [
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
      ]
    }
  end

  defp delete_card_payload(card, sign_skey) do
    updated =
      signed_user_card(card, sign_skey, %{
        deleted_flag: true,
        owner_timestamp: card.owner_timestamp + 1
      })

    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"user_hash" => card.user_hash},
          "changes" => %{
            "deleted_flag" => updated.deleted_flag,
            "owner_timestamp" => updated.owner_timestamp,
            "sign_b64" => to_base64(updated.sign_b64)
          },
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
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

  defp payload_with_tampered_cert(card, field) do
    tampered_value =
      card
      |> Map.get(field)
      |> byte_size()
      |> :crypto.strong_rand_bytes()
      |> to_base64()

    card
    |> user_card_modified()
    |> Map.put(Atom.to_string(field), tampered_value)
    |> user_card_payload()
  end

  # Crypto helpers

  defp signed_user_card(card, sign_skey, attrs) do
    updated_card = struct(card, attrs)

    sign_b64 =
      updated_card
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    %{updated_card | sign_b64: sign_b64}
  end

  defp to_base64(bin), do: Base.encode64(bin, padding: false)

  # Request helpers

  defp insert_card(conn, card, sign_skey) do
    payload = user_card_payload(user_card_modified(card))
    result = post_ingest(conn, payload, sign_skey)
    assert result.status == 200
    result
  end

  defp post_ingest(conn, payload, sign_skey) do
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
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end

  defp post_without_auth(conn, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end

  # Assertion helpers

  defp assert_invalid_signature(conn) do
    assert conn.status == 422

    assert %{"error" => "validation_failed", "details" => %{"sign_b64" => error_msgs}} =
             Jason.decode!(conn.resp_body)

    assert Enum.any?(List.wrap(error_msgs), &String.contains?(&1, "invalid signature"))
  end
end

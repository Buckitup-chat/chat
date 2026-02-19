defmodule ChatWeb.ElectricControllerTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.User, as: UserData

  describe "sunny day scenarios" do
    test "POST /electric/v1/ingest with valid mutations returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      payload = user_card_payload(user_card_modified(card))

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with valid update mutation returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Update the name
      update_payload = update_name_payload(card.user_hash, "Bob Updated")
      update_conn = post_ingest(conn, update_payload, identity.sign_skey)

      assert update_conn.status == 200, update_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(update_conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with valid delete mutation returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Delete the card
      delete_payload = delete_card_payload(card.user_hash)
      delete_conn = post_ingest(conn, delete_payload, identity.sign_skey)

      assert delete_conn.status == 200, delete_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(delete_conn.resp_body)
      assert is_integer(txid)
    end
  end

  describe "error checking scenarios" do
    test "POST /electric/v1/ingest with invalid payload returns 400", %{conn: conn} do
      conn = post(conn, "/electric/v1/ingest", %{})

      assert conn.status == 400
      assert conn.resp_body == "invalid_payload"
    end

    test "POST /electric/v1/ingest with missing name returns 422 and details", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

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

    test "POST /electric/v1/ingest with duplicate user_hash returns 422", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      payload = user_card_payload(user_card_modified(card))

      first_conn = post_ingest(conn, payload, identity.sign_skey)
      assert first_conn.status == 200

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 422

      assert %{"error" => "validation_failed", "details" => %{"user_hash" => _}} =
               Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with invalid pub_key returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")

      payload =
        identity
        |> UserData.extract_pq_card()
        |> user_card_modified()
        |> Map.put("sign_pkey", "\\xzz")
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "invalid_binary_field"
    end

    test "POST /electric/v1/ingest with tampered user_hash returns 422", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Tamper with user_hash: Keep prefix (0x01) and length (65), but change content
      <<prefix, _rest::binary>> = card.user_hash
      tampered_bin = <<prefix, :crypto.strong_rand_bytes(64)::binary>>
      tampered_hash = to_hex_escape(tampered_bin)

      payload =
        card
        |> user_card_modified()
        |> Map.put("user_hash", tampered_hash)
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 422

      assert %{"error" => "validation_failed", "details" => %{"user_hash" => error_msgs}} =
               Jason.decode!(conn.resp_body)

      assert "invalid_user_card_integrity" in error_msgs
    end

    test "POST /electric/v1/ingest with invalid crypt_cert returns 422", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Tamper with crypt_cert: random bytes of same length
      tampered_cert =
        card.crypt_cert
        |> byte_size()
        |> :crypto.strong_rand_bytes()
        |> to_hex_escape()

      payload =
        card
        |> user_card_modified()
        |> Map.put("crypt_cert", tampered_cert)
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 422

      assert %{"error" => "validation_failed", "details" => %{"user_hash" => error_msgs}} =
               Jason.decode!(conn.resp_body)

      assert "invalid_user_card_integrity" in error_msgs
    end

    test "POST /electric/v1/ingest with invalid contact_cert returns 422", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Tamper with contact_cert: random bytes of same length
      tampered_cert =
        card.contact_cert
        |> byte_size()
        |> :crypto.strong_rand_bytes()
        |> to_hex_escape()

      payload =
        card
        |> user_card_modified()
        |> Map.put("contact_cert", tampered_cert)
        |> user_card_payload()

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 422

      assert %{"error" => "validation_failed", "details" => %{"user_hash" => error_msgs}} =
               Jason.decode!(conn.resp_body)

      assert "invalid_user_card_integrity" in error_msgs
    end

    test "POST /electric/v1/ingest update with invalid PoP returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to update with wrong signature (different user's key)
      other_identity = UserData.generate_pq_identity("Alice")
      update_payload = update_name_payload(card.user_hash, "Hacked Name")
      update_conn = post_ingest(conn, update_payload, other_identity.sign_skey)

      assert update_conn.status == 400
      assert update_conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest update without PoP returns 401", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to update without auth
      update_payload = update_name_payload(card.user_hash, "Hacked Name")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(update_payload))

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest delete with invalid PoP returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to delete with wrong signature (different user's key)
      other_identity = UserData.generate_pq_identity("Alice")
      delete_payload = delete_card_payload(card.user_hash)
      delete_conn = post_ingest(conn, delete_payload, other_identity.sign_skey)

      assert delete_conn.status == 400
      assert delete_conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest delete without PoP returns 401", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      insert_payload = user_card_payload(user_card_modified(card))

      # Insert the card first
      insert_conn = post_ingest(conn, insert_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to delete without auth
      delete_payload = delete_card_payload(card.user_hash)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(delete_payload))

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end
  end

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

  defp update_name_payload(user_hash, new_name) do
    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"user_hash" => to_hex_escape(user_hash)},
          "changes" => %{"name" => new_name},
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
  end

  defp delete_card_payload(user_hash) do
    %{
      "mutations" => [
        %{
          "type" => "delete",
          "original" => %{"user_hash" => to_hex_escape(user_hash)},
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
  end

  defp user_card_modified(card) do
    %{
      "user_hash" => to_hex_escape(card.user_hash),
      "sign_pkey" => to_hex_escape(card.sign_pkey),
      "contact_pkey" => to_hex_escape(card.contact_pkey),
      "contact_cert" => to_hex_escape(card.contact_cert),
      "crypt_pkey" => to_hex_escape(card.crypt_pkey),
      "crypt_cert" => to_hex_escape(card.crypt_cert),
      "name" => card.name
    }
  end

  defp to_hex_escape(bin), do: "\\x" <> Base.encode16(bin, case: :lower)

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
end

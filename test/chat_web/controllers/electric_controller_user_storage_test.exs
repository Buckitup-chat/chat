defmodule ChatWeb.ElectricControllerUserStorageTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User, as: UserData

  describe "user storage insert operations" do
    test "POST /electric/v1/ingest with valid user_storage insert returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # First insert the user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Now insert user storage
      uuid = Ecto.UUID.generate()
      value = "encrypted_blob_here"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)

      conn = post_ingest(conn, storage_payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with large value succeeds", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Insert storage with large value (1MB - well under 10MB limit)
      uuid = Ecto.UUID.generate()
      value = :crypto.strong_rand_bytes(1_048_576)
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)

      conn = post_ingest(conn, storage_payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
    end

    test "POST /electric/v1/ingest with duplicate UUID returns 422", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Insert first storage entry
      uuid = Ecto.UUID.generate()
      value = "encrypted_blob_1"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)
      first_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert first_conn.status == 200

      # Try to insert with same UUID — unique constraint violation
      duplicate_payload = user_storage_insert_payload_with_timestamp(
        card.user_hash, uuid, "different_value", identity.sign_skey, System.system_time(:second) + 1
      )
      conn = post_ingest(conn, duplicate_payload, identity.sign_skey)

      assert conn.status == 422
      assert %{"error" => "validation_failed"} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with non-existent user_hash returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)
      # Don't insert the user card

      uuid = Ecto.UUID.generate()
      value = "encrypted_blob"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)

      conn = post_ingest(conn, storage_payload, identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest without PoP returns 401", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Try to insert storage without auth
      uuid = Ecto.UUID.generate()
      value = "encrypted_blob"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(storage_payload))

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with wrong user's signature returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Try to insert with different user's key
      other_identity = UserData.generate_pq_identity("Alice")
      uuid = Ecto.UUID.generate()
      value = "encrypted_blob"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)

      conn = post_ingest(conn, storage_payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage update operations" do
    test "POST /electric/v1/ingest with valid update returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Insert storage entry
      uuid = Ecto.UUID.generate()
      value = "original_value"
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Update the value
      update_payload = user_storage_update_payload(card.user_hash, uuid, "updated_value", identity.sign_skey)
      update_conn = post_ingest(conn, update_payload, identity.sign_skey)

      assert update_conn.status == 200, update_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(update_conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest update with wrong user's signature returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card and storage
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      uuid = Ecto.UUID.generate()
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, "original", identity.sign_skey)
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to update with different user's key
      other_identity = UserData.generate_pq_identity("Alice")
      update_payload = user_storage_update_payload(card.user_hash, uuid, "hacked", identity.sign_skey)
      conn = post_ingest(conn, update_payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage delete operations" do
    test "POST /electric/v1/ingest delete is not accepted", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card and storage
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      uuid = Ecto.UUID.generate()
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, "value", identity.sign_skey)
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Delete is not in the accept list for user_storage
      delete_payload = user_storage_delete_payload(card.user_hash, uuid)
      delete_conn = post_ingest(conn, delete_payload, identity.sign_skey)

      assert delete_conn.status == 400
    end
  end

  describe "batch operations" do
    test "POST /electric/v1/ingest with multiple user_storage inserts in batch succeeds", %{
      conn: conn
    } do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      # Insert multiple storage entries in one request
      uuid1 = Ecto.UUID.generate()
      uuid2 = Ecto.UUID.generate()
      uuid3 = Ecto.UUID.generate()

      mutations =
        for {uuid, value} <- [{uuid1, "value1"}, {uuid2, "value2"}, {uuid3, "value3"}] do
          %{"mutations" => [mutation]} = user_storage_insert_payload(card.user_hash, uuid, value, identity.sign_skey)
          mutation
        end

      batch_payload = %{"mutations" => mutations}

      conn = post_ingest(conn, batch_payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end
  end

  # Helper functions
  defp user_storage_insert_payload_with_timestamp(user_hash, uuid, value, sign_skey, owner_timestamp) do
    {sign_b64, sign_hash} = sign_storage(user_hash, uuid, value, false, nil, owner_timestamp, sign_skey)

    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => user_hash,
            "uuid" => uuid,
            "value_b64" => to_base64(value),
            "deleted_flag" => false,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => to_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
  end

  defp user_storage_insert_payload(user_hash, uuid, value, sign_skey) do
    owner_timestamp = System.system_time(:second)
    {sign_b64, sign_hash} = sign_storage(user_hash, uuid, value, false, nil, owner_timestamp, sign_skey)

    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => user_hash,
            "uuid" => uuid,
            "value_b64" => to_base64(value),
            "deleted_flag" => false,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => to_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
  end

  defp user_storage_update_payload(user_hash, uuid, new_value, sign_skey) do
    # Timestamp must be strictly greater than the insert timestamp for versioning
    owner_timestamp = System.system_time(:second) + 1
    {sign_b64, sign_hash} = sign_storage(user_hash, uuid, new_value, false, nil, owner_timestamp, sign_skey)

    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => user_hash,
            "uuid" => uuid
          },
          "changes" => %{
            "value_b64" => to_base64(new_value),
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => to_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
  end

  defp user_storage_delete_payload(user_hash, uuid) do
    %{
      "mutations" => [
        %{
          "type" => "delete",
          "original" => %{
            "user_hash" => user_hash,
            "uuid" => uuid
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
  end

  defp sign_storage(user_hash, uuid, value, deleted_flag, parent_sign_hash, owner_timestamp, sign_skey) do
    storage = %UserStorage{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: value,
      deleted_flag: deleted_flag,
      parent_sign_hash: parent_sign_hash,
      owner_timestamp: owner_timestamp
    }

    sign_b64 =
      storage
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> Chat.Data.Types.UserStorageSignHash.from_binary()

    {sign_b64, sign_hash}
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

  defp to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

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

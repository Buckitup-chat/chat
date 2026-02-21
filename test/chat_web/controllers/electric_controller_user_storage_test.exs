defmodule ChatWeb.ElectricControllerUserStorageTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)

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
      value = :crypto.strong_rand_bytes(1_048_576) |> Base.encode64(padding: false)
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)

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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)
      first_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert first_conn.status == 200

      # Try to insert with same UUID
      duplicate_payload = user_storage_insert_payload(card.user_hash, uuid, "different_value")
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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)

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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)

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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)

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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, value)
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Update the value
      update_payload = user_storage_update_payload(card.user_hash, uuid, "updated_value")
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
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, "original")
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to update with different user's key
      other_identity = UserData.generate_pq_identity("Alice")
      update_payload = user_storage_update_payload(card.user_hash, uuid, "hacked")
      conn = post_ingest(conn, update_payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage delete operations" do
    test "POST /electric/v1/ingest with valid delete returns txid", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card and storage
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      uuid = Ecto.UUID.generate()
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, "value")
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Delete the storage entry
      delete_payload = user_storage_delete_payload(card.user_hash, uuid)
      delete_conn = post_ingest(conn, delete_payload, identity.sign_skey)

      assert delete_conn.status == 200, delete_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(delete_conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest delete with wrong user's signature returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      # Insert user card and storage
      card_payload = user_card_payload(user_card_modified(card))
      card_conn = post_ingest(conn, card_payload, identity.sign_skey)
      assert card_conn.status == 200

      uuid = Ecto.UUID.generate()
      storage_payload = user_storage_insert_payload(card.user_hash, uuid, "value")
      insert_conn = post_ingest(conn, storage_payload, identity.sign_skey)
      assert insert_conn.status == 200

      # Try to delete with different user's key
      other_identity = UserData.generate_pq_identity("Alice")
      delete_payload = user_storage_delete_payload(card.user_hash, uuid)
      conn = post_ingest(conn, delete_payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end

    test "POST /electric/v1/ingest batch delete with Alice challenge deleting both Alice and Bob keys - only deletes Alice key", %{
      conn: conn
    } do
      alice_identity = UserData.generate_pq_identity("Alice")
      alice_card = UserData.extract_pq_card(alice_identity)
      bob_identity = UserData.generate_pq_identity("Bob")
      bob_card = UserData.extract_pq_card(bob_identity)

      # Insert Alice's user card and storage
      alice_card_payload = user_card_payload(user_card_modified(alice_card))
      alice_card_conn = post_ingest(conn, alice_card_payload, alice_identity.sign_skey)
      assert alice_card_conn.status == 200

      alice_uuid = Ecto.UUID.generate()
      alice_storage_payload = user_storage_insert_payload(alice_card.user_hash, alice_uuid, "alice_value")
      alice_insert_conn = post_ingest(conn, alice_storage_payload, alice_identity.sign_skey)
      assert alice_insert_conn.status == 200

      # Insert Bob's user card and storage
      bob_card_payload = user_card_payload(user_card_modified(bob_card))
      bob_card_conn = post_ingest(conn, bob_card_payload, bob_identity.sign_skey)
      assert bob_card_conn.status == 200

      bob_uuid = Ecto.UUID.generate()
      bob_storage_payload = user_storage_insert_payload(bob_card.user_hash, bob_uuid, "bob_value")
      bob_insert_conn = post_ingest(conn, bob_storage_payload, bob_identity.sign_skey)
      assert bob_insert_conn.status == 200

      # Try to delete both Alice and Bob keys in batch with Alice's signature
      batch_delete_payload = %{
        "mutations" => [
          %{
            "type" => "delete",
            "original" => %{
              "user_hash" => to_hex_escape(alice_card.user_hash),
              "uuid" => alice_uuid
            },
            "syncMetadata" => %{"relation" => "user_storage"}
          },
          %{
            "type" => "delete",
            "original" => %{
              "user_hash" => to_hex_escape(bob_card.user_hash),
              "uuid" => bob_uuid
            },
            "syncMetadata" => %{"relation" => "user_storage"}
          }
        ]
      }

      delete_conn = post_ingest(conn, batch_delete_payload, alice_identity.sign_skey)

      # Should fail because Alice can't delete Bob's key
      assert delete_conn.status == 400
      assert delete_conn.resp_body == "Invalid operation"

      # Verify Bob's storage still exists
      import Ecto.Query
      alias Chat.Data.Schemas.UserStorage

      bob_storage =
        Chat.Db.repo().one(
          from(s in UserStorage,
            where: s.user_hash == ^bob_card.user_hash and s.uuid == ^bob_uuid
          )
        )

      assert bob_storage != nil
      assert bob_storage.value == "bob_value"
    end
  end

  describe "batch operations" do
    test "POST /electric/v1/ingest with multiple user_storage inserts in batch succeeds", %{conn: conn} do
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

      batch_payload = %{
        "mutations" => [
          %{
            "type" => "insert",
            "modified" => %{
              "user_hash" => to_hex_escape(card.user_hash),
              "uuid" => uuid1,
              "value" => "value1"
            },
            "syncMetadata" => %{"relation" => "user_storage"}
          },
          %{
            "type" => "insert",
            "modified" => %{
              "user_hash" => to_hex_escape(card.user_hash),
              "uuid" => uuid2,
              "value" => "value2"
            },
            "syncMetadata" => %{"relation" => "user_storage"}
          },
          %{
            "type" => "insert",
            "modified" => %{
              "user_hash" => to_hex_escape(card.user_hash),
              "uuid" => uuid3,
              "value" => "value3"
            },
            "syncMetadata" => %{"relation" => "user_storage"}
          }
        ]
      }

      conn = post_ingest(conn, batch_payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end
  end

  # Helper functions
  defp user_storage_insert_payload(user_hash, uuid, value) do
    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => to_hex_escape(user_hash),
            "uuid" => uuid,
            "value" => value
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
  end

  defp user_storage_update_payload(user_hash, uuid, new_value) do
    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => to_hex_escape(user_hash),
            "uuid" => uuid
          },
          "changes" => %{"value" => new_value},
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
            "user_hash" => to_hex_escape(user_hash),
            "uuid" => uuid
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]
    }
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
      "user_hash" => to_hex_escape(card.user_hash),
      "sign_pkey" => to_hex_escape(card.sign_pkey),
      "contact_pkey" => to_hex_escape(card.contact_pkey),
      "contact_cert" => to_hex_escape(card.contact_cert),
      "crypt_pkey" => to_hex_escape(card.crypt_pkey),
      "crypt_cert" => to_hex_escape(card.crypt_cert),
      "name" => card.name
    }
  end

  defp to_hex_escape(bin) when is_binary(bin), do: "\\x" <> Base.encode16(bin, case: :lower)

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

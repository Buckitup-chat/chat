defmodule ChatWeb.ElectricControllerUserStorageTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestFixtures, only: [user_card_modified: 1, user_card_payload: 1]
  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3]

  import Chat.Test.UserStorageIngestFixtures,
    only: [
      user_storage_delete_payload: 2,
      user_storage_insert_payload: 4,
      user_storage_insert_payload: 5,
      user_storage_update_payload: 4
    ]

  alias Chat.Data.User, as: UserData

  describe "user storage insert operations" do
    setup %{conn: conn} do
      insert_user_card!(conn)
    end

    test "POST /electric/v1/ingest with valid user_storage insert returns txid", ctx do
      uuid = Ecto.UUID.generate()

      payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "encrypted_blob_here",
          ctx.identity.sign_skey
        )

      conn = post_ingest(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest with large value succeeds", ctx do
      uuid = Ecto.UUID.generate()
      value = :crypto.strong_rand_bytes(1_048_576)

      payload =
        user_storage_insert_payload(ctx.card.user_hash, uuid, value, ctx.identity.sign_skey)

      conn = post_ingest(ctx.conn, payload, ctx.identity.sign_skey)

      assert conn.status == 200, conn.resp_body
    end

    test "POST /electric/v1/ingest with duplicate UUID returns 409", ctx do
      uuid = Ecto.UUID.generate()

      payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "encrypted_blob_1",
          ctx.identity.sign_skey
        )

      first_conn = post_ingest(ctx.conn, payload, ctx.identity.sign_skey)
      assert first_conn.status == 200

      duplicate_payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "different_value",
          ctx.identity.sign_skey,
          System.system_time(:second) + 1
        )

      conn = post_ingest(ctx.conn, duplicate_payload, ctx.identity.sign_skey)

      assert conn.status == 409
      assert %{"status" => "exists", "conflicted" => true} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest without PoP returns 401", ctx do
      uuid = Ecto.UUID.generate()

      payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "encrypted_blob",
          ctx.identity.sign_skey
        )

      conn =
        ctx.conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(payload))

      assert conn.status == 401
      assert %{"error" => "Missing user PoP auth"} = Jason.decode!(conn.resp_body)
    end

    test "POST /electric/v1/ingest with wrong user's signature returns 400", ctx do
      other_identity = UserData.generate_pq_identity("Alice")
      uuid = Ecto.UUID.generate()

      payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "encrypted_blob",
          ctx.identity.sign_skey
        )

      conn = post_ingest(ctx.conn, payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage insert without existing card" do
    test "POST /electric/v1/ingest with non-existent user_hash returns 400", %{conn: conn} do
      identity = UserData.generate_pq_identity("Bob")
      card = UserData.extract_pq_card(identity)

      uuid = Ecto.UUID.generate()

      payload =
        user_storage_insert_payload(card.user_hash, uuid, "encrypted_blob", identity.sign_skey)

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage update operations" do
    setup %{conn: conn} do
      insert_user_card!(conn)
    end

    test "POST /electric/v1/ingest with valid update returns txid", ctx do
      uuid = Ecto.UUID.generate()

      insert_payload =
        user_storage_insert_payload(
          ctx.card.user_hash,
          uuid,
          "original_value",
          ctx.identity.sign_skey
        )

      insert_conn = post_ingest(ctx.conn, insert_payload, ctx.identity.sign_skey)
      assert insert_conn.status == 200

      update_payload =
        user_storage_update_payload(
          ctx.card.user_hash,
          uuid,
          "updated_value",
          ctx.identity.sign_skey
        )

      update_conn = post_ingest(ctx.conn, update_payload, ctx.identity.sign_skey)

      assert update_conn.status == 200, update_conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(update_conn.resp_body)
      assert is_integer(txid)
    end

    test "POST /electric/v1/ingest update with wrong user's signature returns 400", ctx do
      uuid = Ecto.UUID.generate()

      insert_payload =
        user_storage_insert_payload(ctx.card.user_hash, uuid, "original", ctx.identity.sign_skey)

      insert_conn = post_ingest(ctx.conn, insert_payload, ctx.identity.sign_skey)
      assert insert_conn.status == 200

      other_identity = UserData.generate_pq_identity("Alice")

      update_payload =
        user_storage_update_payload(ctx.card.user_hash, uuid, "hacked", ctx.identity.sign_skey)

      conn = post_ingest(ctx.conn, update_payload, other_identity.sign_skey)

      assert conn.status == 400
      assert conn.resp_body == "Invalid operation"
    end
  end

  describe "user storage delete operations" do
    setup %{conn: conn} do
      insert_user_card!(conn)
    end

    test "POST /electric/v1/ingest delete is not accepted", ctx do
      uuid = Ecto.UUID.generate()

      insert_payload =
        user_storage_insert_payload(ctx.card.user_hash, uuid, "value", ctx.identity.sign_skey)

      insert_conn = post_ingest(ctx.conn, insert_payload, ctx.identity.sign_skey)
      assert insert_conn.status == 200

      delete_payload = user_storage_delete_payload(ctx.card.user_hash, uuid)
      delete_conn = post_ingest(ctx.conn, delete_payload, ctx.identity.sign_skey)

      assert delete_conn.status == 400
    end
  end

  describe "batch operations" do
    setup %{conn: conn} do
      insert_user_card!(conn)
    end

    test "POST /electric/v1/ingest with multiple user_storage inserts in batch succeeds", ctx do
      mutations =
        for {uuid, value} <- [
              {Ecto.UUID.generate(), "value1"},
              {Ecto.UUID.generate(), "value2"},
              {Ecto.UUID.generate(), "value3"}
            ] do
          %{"mutations" => [mutation]} =
            user_storage_insert_payload(ctx.card.user_hash, uuid, value, ctx.identity.sign_skey)

          mutation
        end

      batch_payload = %{"mutations" => mutations}
      conn = post_ingest(ctx.conn, batch_payload, ctx.identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end
  end

  defp insert_user_card!(conn) do
    identity = UserData.generate_pq_identity("Bob")
    card = UserData.extract_pq_card(identity)

    %{status: 200} =
      post_ingest(conn, user_card_payload(user_card_modified(card)), identity.sign_skey)

    %{identity: identity, card: card}
  end
end

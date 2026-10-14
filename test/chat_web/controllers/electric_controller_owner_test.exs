defmodule ChatWeb.ElectricControllerOwnerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  alias Chat.AdminDb
  alias Chat.Challenge
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Pq.OwnerBootstrap

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    prev = AdminDb.get(:pq_admin)
    CubDB.delete(AdminDb.db(), :pq_admin)

    on_exit(fn ->
      if prev,
        do: AdminDb.put(:pq_admin, prev),
        else: CubDB.delete(AdminDb.db(), :pq_admin)
    end)
  end

  describe "ingest" do
    test "a person's card ingested here makes them the owner", %{conn: conn} do
      identity = User.generate_pq_identity("Alice")
      card = User.extract_pq_card(identity)

      conn = ingest_card(conn, card, identity)

      assert %{"txid" => _} = json_response(conn, 200)
      assert owner_hash() == card.user_hash
    end

    test "a peer's SyncBot card pushed here does not become the owner", %{conn: conn} do
      identity = User.generate_pq_identity("SyncBot_BK-002")

      conn = ingest_card(conn, User.extract_pq_card(identity), identity)

      assert %{"txid" => _} = json_response(conn, 200)
      assert OwnerBootstrap.owner() == nil
    end
  end

  describe "peer sync" do
    test "a card stored by peer sync does not make its user the owner" do
      card = "Bob" |> User.generate_pq_identity() |> User.extract_pq_card()

      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      assert User.get_card(card.user_hash)
      assert OwnerBootstrap.owner() == nil
    end
  end

  describe "POST /electric/v1/owner_claim" do
    test "a person whose card was synced here claims the device", %{conn: conn} do
      identity = User.generate_pq_identity("Alice")
      card = synced_card(identity)

      conn = claim(conn, card.user_hash, identity.sign_skey)

      assert json_response(conn, 200) == %{"admin" => card.user_hash}
      assert owner_hash() == card.user_hash
    end

    test "a claim signed with another key is refused", %{conn: conn} do
      card = "Alice" |> User.generate_pq_identity() |> synced_card()
      mallory = User.generate_pq_identity("Mallory")

      conn = claim(conn, card.user_hash, mallory.sign_skey)

      assert json_response(conn, 401) == %{"error" => "invalid_signature"}
      assert OwnerBootstrap.owner() == nil
    end

    test "a SyncBot card cannot claim the device", %{conn: conn} do
      identity = User.generate_pq_identity("SyncBot_BK-002")
      card = synced_card(identity)

      conn = claim(conn, card.user_hash, identity.sign_skey)

      assert json_response(conn, 403) == %{"error" => "not_eligible"}
      assert OwnerBootstrap.owner() == nil
    end

    test "a claim does not replace the owner", %{conn: conn} do
      alice_card = "Alice" |> User.generate_pq_identity() |> synced_card()
      bob = User.generate_pq_identity("Bob")
      bob_card = synced_card(bob)
      :registered = OwnerBootstrap.maybe_register_card(alice_card)

      conn = claim(conn, bob_card.user_hash, bob.sign_skey)

      assert json_response(conn, 200) == %{"admin" => alice_card.user_hash}
      assert owner_hash() == alice_card.user_hash
    end
  end

  defp owner_hash do
    case OwnerBootstrap.owner() do
      %{user_hash: user_hash} -> user_hash
      nil -> nil
    end
  end

  defp synced_card(identity) do
    card = User.extract_pq_card(identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp claim(conn, user_hash, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    post(conn, "/electric/v1/owner_claim", %{
      user_hash: user_hash,
      challenge_id: challenge_id,
      signature: challenge |> EnigmaPq.sign(sign_skey) |> b64()
    })
  end

  defp ingest_card(conn, card, identity) do
    {challenge_id, challenge} = Challenge.store()

    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/electric/v1/ingest",
      Jason.encode!(%{
        "auth" => %{
          "challenge_id" => challenge_id,
          "signature" => challenge |> EnigmaPq.sign(identity.sign_skey) |> b64()
        },
        "mutations" => [
          %{
            "type" => "insert",
            "modified" => %{
              "user_hash" => card.user_hash,
              "sign_pkey" => b64(card.sign_pkey),
              "contact_pkey" => b64(card.contact_pkey),
              "contact_cert" => b64(card.contact_cert),
              "crypt_pkey" => b64(card.crypt_pkey),
              "crypt_cert" => b64(card.crypt_cert),
              "name" => card.name,
              "deleted_flag" => card.deleted_flag,
              "owner_timestamp" => card.owner_timestamp,
              "sign_b64" => b64(card.sign_b64)
            },
            "syncMetadata" => %{"relation" => "user_cards"}
          }
        ]
      })
    )
  end

  defp b64(bin), do: Base.encode64(bin, padding: false)
end

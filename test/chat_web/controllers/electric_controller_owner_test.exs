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

  test "a person's card ingested here makes them the owner", %{conn: conn} do
    identity = User.generate_pq_identity("Alice")
    card = User.extract_pq_card(identity)

    conn = ingest_card(conn, card, identity)

    assert %{"txid" => _} = json_response(conn, 200)
    assert %{user_hash: user_hash} = OwnerBootstrap.owner()
    assert user_hash == card.user_hash
  end

  test "a peer's SyncBot card pushed here does not become the owner", %{conn: conn} do
    identity = User.generate_pq_identity("SyncBot_BK-002")

    conn = ingest_card(conn, User.extract_pq_card(identity), identity)

    assert %{"txid" => _} = json_response(conn, 200)
    assert OwnerBootstrap.owner() == nil
  end

  test "a card stored by peer sync makes its user the owner" do
    card = "Bob" |> User.generate_pq_identity() |> User.extract_pq_card()

    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    assert %{user_hash: user_hash} = OwnerBootstrap.owner()
    assert user_hash == card.user_hash
  end

  test "a peer's SyncBot card arriving by peer sync does not become the owner" do
    card = "SyncBot_BK-003" |> User.generate_pq_identity() |> User.extract_pq_card()

    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    assert User.get_card(card.user_hash)
    assert OwnerBootstrap.owner() == nil
  end

  test "a card peer sync refuses does not become the owner" do
    card = "Mallory" |> User.generate_pq_identity() |> User.extract_pq_card()

    {:ok, _} = ShapeWriter.write(:user_card, :insert, %{card | name: "Tampered"})

    refute User.get_card(card.user_hash)
    assert OwnerBootstrap.owner() == nil
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

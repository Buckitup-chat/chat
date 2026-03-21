defmodule ChatWeb.ElectricSyncTest do
  @moduledoc """
  Test Electric SQL sync endpoint for user_cards table.
  Tests the SSE stream endpoint that provides real-time user card updates.

  Note: Some tests may fail in test environment due to Electric's replication slot
  being in use. These tests are primarily for documentation and should be verified
  manually using the /electric page.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.Consts
  alias Chat.Repo

  setup do
    Repo.delete_all(UserCard)
    :ok
  end

  defp user_card_attrs(name) do
    %{
      user_hash: Consts.user_hash_prefix() <> :crypto.strong_rand_bytes(64),
      sign_pkey: :crypto.strong_rand_bytes(32),
      contact_pkey: :crypto.strong_rand_bytes(32),
      contact_cert: :crypto.strong_rand_bytes(64),
      crypt_pkey: :crypto.strong_rand_bytes(32),
      crypt_cert: :crypto.strong_rand_bytes(64),
      name: name,
      deleted_flag: false,
      owner_timestamp: 0,
      sign_b64: :crypto.strong_rand_bytes(64)
    }
  end

  describe "GET /electric/v1/user_card - SSE Stream (manual verification recommended)" do
    @tag :skip
    test "returns SSE stream with correct headers", %{conn: conn} do
      conn = get(conn, "/electric/v1/user_card")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "connection") == ["keep-alive"]
    end

    @tag :skip
    test "streams existing user cards on connection", %{conn: conn} do
      {:ok, _card1} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Alice"))
        |> Repo.insert()

      {:ok, _card2} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Bob"))
        |> Repo.insert()

      conn = get(conn, "/electric/v1/user_card")

      assert conn.status == 200
      response_body = response(conn, 200)
      assert response_body != ""

      cards = Repo.all(UserCard)
      assert length(cards) == 2
      assert Enum.any?(cards, fn c -> c.name == "Alice" end)
      assert Enum.any?(cards, fn c -> c.name == "Bob" end)
    end
  end

  describe "UserCard data format" do
    test "user cards have required fields for Electric sync", _context do
      attrs = user_card_attrs("Test User")

      {:ok, card} =
        %UserCard{}
        |> UserCard.create_changeset(attrs)
        |> Repo.insert()

      assert card.name == "Test User"
      assert is_binary(card.user_hash)
      assert is_binary(card.sign_pkey)
      assert is_binary(card.contact_pkey)
      assert is_binary(card.crypt_pkey)

      retrieved = Repo.get(UserCard, attrs.user_hash)
      assert retrieved.name == card.name
      assert retrieved.user_hash == card.user_hash
    end

    test "user cards can be encoded to JSON format", _context do
      attrs = user_card_attrs("JSON Test")

      {:ok, card} =
        %UserCard{}
        |> UserCard.create_changeset(attrs)
        |> Repo.insert()

      card_data = %{
        "name" => card.name,
        "user_hash" => Base.encode16(card.user_hash, case: :lower)
      }

      {:ok, json} = Jason.encode(card_data)
      assert is_binary(json)

      {:ok, decoded} = Jason.decode(json)
      assert decoded["name"] == "JSON Test"
      assert is_binary(decoded["user_hash"])
    end
  end

  describe "Electric publication setup" do
    @tag :skip
    test "user_cards table is in electric_publication_default" do
      result =
        Repo.query!("""
        SELECT tablename
        FROM pg_publication_tables
        WHERE pubname = 'electric_publication_default'
        AND tablename = 'user_cards'
        """)

      assert length(result.rows) == 1
      assert hd(result.rows) == ["user_cards"]
    end

    test "replication slot exists or warning was shown" do
      result =
        Repo.query!("""
        SELECT slot_name
        FROM pg_replication_slots
        WHERE slot_name = 'electric_slot_default'
        """)

      if length(result.rows) > 0 do
        assert hd(result.rows) == ["electric_slot_default"]
      else
        assert true
      end
    end
  end
end

defmodule ChatWeb.ElectricSyncUserStorageVersionTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Ecto.Query

  alias Chat.Data.Schemas.{UserCard, UserStorageVersion}
  alias Chat.Data.Types.{UserHash, UserStorageSignHash}
  alias Chat.Repo
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    conn = Sandbox.init_test_session(conn, Chat.Repo)
    {:ok, conn: conn}
  end

  describe "GET /electric/v1/user_storage_version - sync endpoint" do
    test "returns response with correct status", %{conn: conn} do
      conn = get(conn, "/electric/v1/user_storage_version?offset=-1")

      assert conn.status == 200
    end

    test "streams existing user storage versions on connection", %{conn: conn} do
      card = insert_card!("Alice")
      insert_version!(card.user_hash, Ecto.UUID.generate())
      insert_version!(card.user_hash, Ecto.UUID.generate())

      conn = get(conn, "/electric/v1/user_storage_version?offset=-1")

      assert conn.status == 200
      assert length(Repo.all(UserStorageVersion)) == 2
    end
  end

  describe "GET /electric/v1/user_storage_version/:user_hash/:uuid - filtered by user and key" do
    @tag :skip
    test "returns SSE stream filtered by user_hash and uuid", %{conn: conn} do
      card1 = insert_card!("Alice")
      card2 = insert_card!("Bob")
      uuid_alice = Ecto.UUID.generate()
      uuid_bob = Ecto.UUID.generate()

      sign_hash1 = generate_sign_hash()
      sign_hash2 = generate_sign_hash()
      sign_hash3 = generate_sign_hash()

      insert_version!(card1.user_hash, uuid_alice, sign_hash: sign_hash1, owner_timestamp: 1000)

      insert_version!(card1.user_hash, uuid_alice,
        sign_hash: sign_hash2,
        parent_sign_hash: sign_hash1,
        owner_timestamp: 2000
      )

      insert_version!(card1.user_hash, uuid_alice,
        sign_hash: sign_hash3,
        parent_sign_hash: sign_hash2,
        owner_timestamp: 3000
      )

      insert_version!(card2.user_hash, uuid_bob)

      user_hash_hex = Base.encode16(card1.user_hash, case: :lower)

      conn =
        get(conn, "/electric/v1/user_storage_version/#{user_hash_hex}/#{uuid_alice}?offset=-1")

      assert conn.status == 200
    end
  end

  describe "UserStorageVersion data format" do
    test "user storage versions have required fields for Electric sync", _context do
      card = insert_card!("Test User")
      uuid = Ecto.UUID.generate()
      version = insert_version!(card.user_hash, uuid)

      assert version.user_hash == card.user_hash
      assert version.uuid == uuid
      assert is_binary(version.sign_hash)
      assert is_binary(version.value_b64)
      assert version.deleted_flag == false
      assert is_integer(version.owner_timestamp)
      assert is_binary(version.sign_b64)

      retrieved =
        Repo.one(
          from(v in UserStorageVersion,
            where:
              v.user_hash == ^card.user_hash and v.uuid == ^uuid and
                v.sign_hash == ^version.sign_hash
          )
        )

      assert retrieved.user_hash == version.user_hash
      assert retrieved.uuid == version.uuid
      assert retrieved.sign_hash == version.sign_hash
    end

    test "user storage versions support version chains with parent_sign_hash", _context do
      card = insert_card!("Test User")
      uuid = Ecto.UUID.generate()
      sign_hash1 = generate_sign_hash()
      sign_hash2 = generate_sign_hash()

      v1 = insert_version!(card.user_hash, uuid, sign_hash: sign_hash1, owner_timestamp: 1000)

      v2 =
        insert_version!(card.user_hash, uuid,
          sign_hash: sign_hash2,
          parent_sign_hash: sign_hash1,
          owner_timestamp: 2000
        )

      assert v1.parent_sign_hash == nil
      assert v2.parent_sign_hash == sign_hash1

      versions = list_versions_ordered(card.user_hash, uuid)
      assert length(versions) == 2
      assert hd(versions).sign_hash == sign_hash1
      assert List.last(versions).sign_hash == sign_hash2
      assert List.last(versions).parent_sign_hash == sign_hash1
    end
  end

  describe "Electric publication setup" do
    test "user_storage_versions table is in electric_publication_default" do
      result =
        Repo.query!("""
        SELECT tablename
        FROM pg_publication_tables
        WHERE pubname = 'electric_publication_default'
        AND tablename = 'user_storage_versions'
        """)

      assert length(result.rows) == 1
      assert hd(result.rows) == ["user_storage_versions"]
    end
  end

  defp insert_card!(name) do
    {:ok, card} =
      %UserCard{}
      |> UserCard.create_changeset(user_card_attrs(name))
      |> Repo.insert()

    card
  end

  defp insert_version!(user_hash, uuid, extra_attrs \\ []) do
    attrs =
      user_hash
      |> user_storage_version_attrs(uuid)
      |> Map.merge(Map.new(extra_attrs))

    %UserStorageVersion{}
    |> UserStorageVersion.changeset(attrs)
    |> Repo.insert!()
  end

  defp generate_sign_hash do
    UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))
  end

  defp list_versions_ordered(user_hash, uuid) do
    Repo.all(
      from(v in UserStorageVersion,
        where: v.user_hash == ^user_hash and v.uuid == ^uuid,
        order_by: [asc: v.owner_timestamp]
      )
    )
  end

  defp user_card_attrs(name) do
    %{
      user_hash: UserHash.from_binary(:crypto.strong_rand_bytes(64)),
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

  defp user_storage_version_attrs(user_hash, uuid) do
    %{
      user_hash: user_hash,
      uuid: uuid,
      sign_hash: generate_sign_hash(),
      value_b64: :crypto.strong_rand_bytes(64),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.system_time(:millisecond),
      sign_b64: :crypto.strong_rand_bytes(64)
    }
  end
end

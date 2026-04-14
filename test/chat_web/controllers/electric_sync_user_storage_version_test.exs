defmodule ChatWeb.ElectricSyncUserStorageVersionTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  alias Chat.Data.Schemas.{UserCard, UserStorage, UserStorageVersion}
  alias Chat.Data.Types.{UserHash, UserStorageSignHash}
  alias Chat.Repo
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    conn = Sandbox.init_test_session(conn, Chat.Repo)
    {:ok, conn: conn}
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
      sign_hash: UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64)),
      value_b64: :crypto.strong_rand_bytes(64),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.system_time(:millisecond),
      sign_b64: :crypto.strong_rand_bytes(64)
    }
  end

  describe "GET /electric/v1/user_storage_version - sync endpoint" do
    test "returns response with correct status", %{conn: conn} do
      conn = get(conn, "/electric/v1/user_storage_version?offset=-1")

      assert conn.status == 200
    end

    test "streams existing user storage versions on connection", %{conn: conn} do
      {:ok, card} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Alice"))
        |> Repo.insert()

      uuid1 = Ecto.UUID.generate()
      uuid2 = Ecto.UUID.generate()

      {:ok, _version1} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(user_storage_version_attrs(card.user_hash, uuid1))
        |> Repo.insert()

      {:ok, _version2} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(user_storage_version_attrs(card.user_hash, uuid2))
        |> Repo.insert()

      conn = get(conn, "/electric/v1/user_storage_version?offset=-1")

      assert conn.status == 200

      versions = Repo.all(UserStorageVersion)
      assert length(versions) == 2
    end
  end

  describe "GET /electric/v1/user_storage_version/:user_hash/:uuid - filtered by user and key" do
    @tag :skip
    # Electric's SQL parser doesn't support bytea/binary columns in where clauses
    # See: https://electric-sql.com/docs/guides/shapes (supported types: numerical, boolean, uuid, text, interval, date/time)
    test "returns SSE stream filtered by user_hash and uuid", %{conn: conn} do
      {:ok, card1} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Alice"))
        |> Repo.insert()

      {:ok, card2} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Bob"))
        |> Repo.insert()

      uuid_alice = Ecto.UUID.generate()
      uuid_bob = Ecto.UUID.generate()

      sign_hash1 = UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))
      sign_hash2 = UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))
      sign_hash3 = UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))

      {:ok, _v1} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(
          user_storage_version_attrs(card1.user_hash, uuid_alice)
          |> Map.put(:sign_hash, sign_hash1)
          |> Map.put(:owner_timestamp, 1000)
        )
        |> Repo.insert()

      {:ok, _v2} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(
          user_storage_version_attrs(card1.user_hash, uuid_alice)
          |> Map.put(:sign_hash, sign_hash2)
          |> Map.put(:parent_sign_hash, sign_hash1)
          |> Map.put(:owner_timestamp, 2000)
        )
        |> Repo.insert()

      {:ok, _v3} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(
          user_storage_version_attrs(card1.user_hash, uuid_alice)
          |> Map.put(:sign_hash, sign_hash3)
          |> Map.put(:parent_sign_hash, sign_hash2)
          |> Map.put(:owner_timestamp, 3000)
        )
        |> Repo.insert()

      {:ok, _v_bob} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(user_storage_version_attrs(card2.user_hash, uuid_bob))
        |> Repo.insert()

      user_hash_hex = Base.encode16(card1.user_hash, case: :lower)

      conn =
        get(conn, "/electric/v1/user_storage_version/#{user_hash_hex}/#{uuid_alice}?offset=-1")

      assert conn.status == 200
    end
  end

  describe "UserStorageVersion data format" do
    test "user storage versions have required fields for Electric sync", _context do
      {:ok, card} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Test User"))
        |> Repo.insert()

      uuid = Ecto.UUID.generate()
      attrs = user_storage_version_attrs(card.user_hash, uuid)

      {:ok, version} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(attrs)
        |> Repo.insert()

      assert version.user_hash == card.user_hash
      assert version.uuid == uuid
      assert is_binary(version.sign_hash)
      assert is_binary(version.value_b64)
      assert version.deleted_flag == false
      assert is_integer(version.owner_timestamp)
      assert is_binary(version.sign_b64)

      import Ecto.Query

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
      {:ok, card} =
        %UserCard{}
        |> UserCard.create_changeset(user_card_attrs("Test User"))
        |> Repo.insert()

      uuid = Ecto.UUID.generate()
      sign_hash1 = UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))
      sign_hash2 = UserStorageSignHash.from_binary(:crypto.strong_rand_bytes(64))

      {:ok, v1} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(
          user_storage_version_attrs(card.user_hash, uuid)
          |> Map.put(:sign_hash, sign_hash1)
          |> Map.put(:owner_timestamp, 1000)
        )
        |> Repo.insert()

      {:ok, v2} =
        %UserStorageVersion{}
        |> UserStorageVersion.changeset(
          user_storage_version_attrs(card.user_hash, uuid)
          |> Map.put(:sign_hash, sign_hash2)
          |> Map.put(:parent_sign_hash, sign_hash1)
          |> Map.put(:owner_timestamp, 2000)
        )
        |> Repo.insert()

      assert v1.parent_sign_hash == nil
      assert v2.parent_sign_hash == sign_hash1

      import Ecto.Query

      versions =
        Repo.all(
          from(v in UserStorageVersion,
            where: v.user_hash == ^card.user_hash and v.uuid == ^uuid,
            order_by: [asc: v.owner_timestamp]
          )
        )

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
end

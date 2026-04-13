defmodule Chat.Data.UserStorageVersioningTest do
  use ChatWeb.DataCase

  import Ecto.Query

  alias Chat.Data.Schemas.{UserCard, UserStorage, UserStorageVersion}
  alias Chat.Data.Types.{UserHash, UserStorageSignHash}
  alias Chat.Data.User
  alias Chat.Repo

  defp compute_sign_hash(sign_b64) do
    sign_b64
    |> EnigmaPq.hash()
    |> UserStorageSignHash.from_binary()
  end

  defp signed_storage(identity, user_hash, attrs \\ %{}) do
    storage =
      %UserStorage{
        user_hash: user_hash,
        uuid: Ecto.UUID.generate(),
        value_b64: "test value",
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: System.system_time(:second)
      }
      |> struct(attrs)

    sign_b64 =
      storage
      |> Chat.Data.Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    sign_hash = compute_sign_hash(sign_b64)
    %{storage | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  describe "user_storage versioning" do
    setup do
      # Create a test user card
      identity = EnigmaPq.generate_identity()

      user_hash =
        identity.sign_pkey
        |> EnigmaPq.hash()
        |> Chat.Data.Types.UserHash.from_binary()

      card_attrs = %{
        user_hash: user_hash,
        sign_pkey: identity.sign_pkey,
        contact_pkey: identity.crypt_pkey,
        contact_cert: <<1, 2, 3>>,
        crypt_pkey: identity.crypt_pkey,
        crypt_cert: <<4, 5, 6>>,
        name: "Test User",
        deleted_flag: false,
        owner_timestamp: System.system_time(:second)
      }

      # Sign the card
      sign_payload = Chat.Data.Integrity.signature_payload(%UserCard{} |> struct(card_attrs))
      sign_b64 = EnigmaPq.sign(sign_payload, identity.sign_skey)

      card =
        %UserCard{}
        |> UserCard.create_changeset(Map.put(card_attrs, :sign_b64, sign_b64))
        |> Repo.insert!()

      %{card: card, identity: identity, user_hash: user_hash}
    end

    test "creates user_storage with versioning fields", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second)

      storage_attrs = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "test value",
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: timestamp
      }

      # Sign the storage
      sign_payload = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs))
      sign_b64 = EnigmaPq.sign(sign_payload, identity.sign_skey)
      sign_hash = compute_sign_hash(sign_b64)

      storage_attrs =
        storage_attrs
        |> Map.put(:sign_b64, sign_b64)
        |> Map.put(:sign_hash, sign_hash)

      storage =
        %UserStorage{}
        |> UserStorage.create_changeset(storage_attrs)
        |> Repo.insert!()

      assert storage.user_hash == user_hash
      assert storage.uuid == uuid
      assert storage.value_b64 == "test value"
      assert storage.deleted_flag == false
      assert storage.parent_sign_hash == nil
      assert storage.owner_timestamp == timestamp
      assert storage.sign_b64 == sign_b64
      assert storage.sign_hash == sign_hash
    end

    test "archives old version when updating with newer timestamp", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp1 = System.system_time(:second)

      # Create first version
      storage_attrs1 = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "version 1",
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: timestamp1
      }

      sign_payload1 = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs1))
      sign_b64_1 = EnigmaPq.sign(sign_payload1, identity.sign_skey)
      sign_hash_1 = compute_sign_hash(sign_b64_1)

      storage1 =
        %UserStorage{}
        |> UserStorage.create_changeset(
          storage_attrs1
          |> Map.put(:sign_b64, sign_b64_1)
          |> Map.put(:sign_hash, sign_hash_1)
        )
        |> Repo.insert!()

      # Create second version with newer timestamp
      timestamp2 = timestamp1 + 10

      storage_attrs2 = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "version 2",
        deleted_flag: false,
        parent_sign_hash: sign_hash_1,
        owner_timestamp: timestamp2
      }

      sign_payload2 = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs2))
      sign_b64_2 = EnigmaPq.sign(sign_payload2, identity.sign_skey)
      sign_hash_2 = compute_sign_hash(sign_b64_2)

      # First archive the old version
      %UserStorageVersion{}
      |> UserStorageVersion.changeset(%{
        user_hash: storage1.user_hash,
        uuid: storage1.uuid,
        sign_hash: storage1.sign_hash,
        value_b64: storage1.value_b64,
        deleted_flag: storage1.deleted_flag,
        parent_sign_hash: storage1.parent_sign_hash,
        owner_timestamp: storage1.owner_timestamp,
        sign_b64: storage1.sign_b64
      })
      |> Repo.insert!()

      # Then update main table
      storage2 =
        storage1
        |> UserStorage.update_changeset(%{
          value_b64: "version 2",
          deleted_flag: false,
          parent_sign_hash: sign_hash_1,
          owner_timestamp: timestamp2,
          sign_b64: sign_b64_2,
          sign_hash: sign_hash_2
        })
        |> Repo.update!()

      # Verify main table has latest version
      assert storage2.value_b64 == "version 2"
      assert storage2.owner_timestamp == timestamp2
      assert storage2.parent_sign_hash == sign_hash_1

      # Verify old version is in versions table
      version = Repo.get_by(UserStorageVersion, user_hash: user_hash, uuid: uuid, sign_hash: sign_hash_1)
      assert version != nil
      assert version.value_b64 == "version 1"
      assert version.owner_timestamp == timestamp1
    end

    test "foreign key constraint prevents invalid parent_sign_hash", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second)
      invalid_parent_hash =
        :crypto.strong_rand_bytes(64)
        |> UserStorageSignHash.from_binary()

      storage_attrs = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "test value",
        deleted_flag: false,
        parent_sign_hash: invalid_parent_hash,
        owner_timestamp: timestamp
      }

      sign_payload = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs))
      sign_b64 = EnigmaPq.sign(sign_payload, identity.sign_skey)
      sign_hash = compute_sign_hash(sign_b64)

      # This should fail due to FK constraint
      assert_raise Ecto.InvalidChangesetError, fn ->
        %UserStorage{}
        |> UserStorage.create_changeset(
          storage_attrs
          |> Map.put(:sign_b64, sign_b64)
          |> Map.put(:sign_hash, sign_hash)
        )
        |> Repo.insert!()
      end
    end

    test "signature verification works", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second)

      storage_attrs = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "test value",
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: timestamp
      }

      # Sign correctly
      sign_payload = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs))
      sign_b64 = EnigmaPq.sign(sign_payload, identity.sign_skey)
      sign_hash = compute_sign_hash(sign_b64)

      storage =
        %UserStorage{}
        |> struct(
          storage_attrs
          |> Map.put(:sign_b64, sign_b64)
          |> Map.put(:sign_hash, sign_hash)
        )

      # Verify signature
      assert Chat.Data.Integrity.verify_signature(storage) == :ok
    end

    test "insert_storage upserts with newer timestamp on conflict", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})

      changeset1 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage1))
      {:ok, _} = User.insert_storage(changeset1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      changeset2 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage2))
      {:ok, _} = User.insert_storage(changeset2)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "v2"
      assert stored.owner_timestamp == storage2.owner_timestamp
    end

    test "insert_storage ignores older timestamp on conflict", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second) + 100

      storage1 =
        signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "newer", owner_timestamp: timestamp})

      changeset1 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage1))
      {:ok, _} = User.insert_storage(changeset1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "older",
          owner_timestamp: timestamp - 50
        })

      changeset2 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage2))
      {:ok, _} = User.insert_storage(changeset2)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "newer"
      assert stored.owner_timestamp == timestamp
    end

    test "insert_storage_with_conflict replaces main when newer and archives existing", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})

      changeset1 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage1))
      {:ok, inserted} = Repo.insert(changeset1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "v2"

      version =
        Repo.get_by(UserStorageVersion, user_hash: user_hash, uuid: uuid, sign_hash: storage1.sign_hash)

      assert version != nil
      assert version.value_b64 == "v1"
    end

    test "insert_storage_with_conflict archives new when older and keeps existing", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second) + 100

      storage1 =
        signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "newer", owner_timestamp: timestamp})

      changeset1 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage1))
      {:ok, inserted} = Repo.insert(changeset1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "older",
          owner_timestamp: timestamp - 50
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "newer"

      version =
        Repo.get_by(UserStorageVersion, user_hash: user_hash, uuid: uuid, sign_hash: storage2.sign_hash)

      assert version != nil
      assert version.value_b64 == "older"
    end

    test "duplicate archive insert is idempotent", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})

      changeset1 = UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage1))
      {:ok, inserted} = Repo.insert(changeset1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)
      # Repeat the same conflict resolution — should not fail
      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      versions =
        Repo.all(
          from v in UserStorageVersion,
            where: v.user_hash == ^user_hash and v.uuid == ^uuid
        )

      assert length(versions) == 1
    end

    test "soft delete sets deleted_flag", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      timestamp1 = System.system_time(:second)

      # Create storage
      storage_attrs1 = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "test value",
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: timestamp1
      }

      sign_payload1 = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs1))
      sign_b64_1 = EnigmaPq.sign(sign_payload1, identity.sign_skey)
      sign_hash_1 = compute_sign_hash(sign_b64_1)

      storage1 =
        %UserStorage{}
        |> UserStorage.create_changeset(
          storage_attrs1
          |> Map.put(:sign_b64, sign_b64_1)
          |> Map.put(:sign_hash, sign_hash_1)
        )
        |> Repo.insert!()

      # Archive old version first (required by FK constraint)
      %UserStorageVersion{}
      |> UserStorageVersion.changeset(%{
        user_hash: storage1.user_hash,
        uuid: storage1.uuid,
        sign_hash: storage1.sign_hash,
        value_b64: storage1.value_b64,
        deleted_flag: storage1.deleted_flag,
        parent_sign_hash: storage1.parent_sign_hash,
        owner_timestamp: storage1.owner_timestamp,
        sign_b64: storage1.sign_b64
      })
      |> Repo.insert!()

      # Soft delete
      timestamp2 = timestamp1 + 10

      storage_attrs2 = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: "test value",
        deleted_flag: true,
        parent_sign_hash: sign_hash_1,
        owner_timestamp: timestamp2
      }

      sign_payload2 = Chat.Data.Integrity.signature_payload(%UserStorage{} |> struct(storage_attrs2))
      sign_b64_2 = EnigmaPq.sign(sign_payload2, identity.sign_skey)
      sign_hash_2 = compute_sign_hash(sign_b64_2)

      storage2 =
        storage1
        |> UserStorage.update_changeset(%{
          deleted_flag: true,
          parent_sign_hash: sign_hash_1,
          owner_timestamp: timestamp2,
          sign_b64: sign_b64_2,
          sign_hash: sign_hash_2
        })
        |> Repo.update!()

      assert storage2.deleted_flag == true
      assert storage2.owner_timestamp == timestamp2
    end
  end
end

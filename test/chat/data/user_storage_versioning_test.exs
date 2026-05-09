defmodule Chat.Data.UserStorageVersioningTest do
  use ChatWeb.DataCase

  import Ecto.Query

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.{UserCard, UserStorage, UserStorageVersion}
  alias Chat.Data.Types.{UserHash, UserStorageSignHash}
  alias Chat.Data.User
  alias Chat.Data.User.Validation
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
      |> Integrity.signature_payload()
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
        |> UserHash.from_binary()

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
      sign_payload = Integrity.signature_payload(%UserCard{} |> struct(card_attrs))
      sign_b64 = EnigmaPq.sign(sign_payload, identity.sign_skey)

      card =
        %UserCard{}
        |> UserCard.create_changeset(Map.put(card_attrs, :sign_b64, sign_b64))
        |> Repo.insert!()

      %{card: card, identity: identity, user_hash: user_hash}
    end

    test "creates user_storage with versioning fields", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second)

      storage =
        identity
        |> signed_storage(user_hash, %{uuid: uuid, owner_timestamp: timestamp})
        |> insert_storage!()

      assert storage.user_hash == user_hash
      assert storage.uuid == uuid
      assert storage.value_b64 == "test value"
      assert storage.deleted_flag == false
      assert storage.parent_sign_hash == nil
      assert storage.owner_timestamp == timestamp
      assert storage.sign_b64 != nil
      assert storage.sign_hash != nil
    end

    test "archives old version when updating with newer timestamp", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()

      storage1 =
        insert_storage!(
          signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "version 1"})
        )

      archive_storage!(storage1)

      v2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "version 2",
          parent_sign_hash: storage1.sign_hash,
          owner_timestamp: storage1.owner_timestamp + 10
        })

      storage2 =
        storage1
        |> UserStorage.update_changeset(
          Map.from_struct(v2)
          |> Map.take(
            ~w(value_b64 deleted_flag parent_sign_hash owner_timestamp sign_b64 sign_hash)a
          )
        )
        |> Repo.update!()

      assert storage2.value_b64 == "version 2"
      assert storage2.owner_timestamp == storage1.owner_timestamp + 10
      assert storage2.parent_sign_hash == storage1.sign_hash

      version =
        Repo.get_by(UserStorageVersion,
          user_hash: user_hash,
          uuid: uuid,
          sign_hash: storage1.sign_hash
        )

      assert version != nil
      assert version.value_b64 == "version 1"
      assert version.owner_timestamp == storage1.owner_timestamp
    end

    test "foreign key constraint prevents invalid parent_sign_hash", %{
      user_hash: user_hash,
      identity: identity
    } do
      invalid_parent_hash =
        :crypto.strong_rand_bytes(64)
        |> UserStorageSignHash.from_binary()

      storage = signed_storage(identity, user_hash, %{parent_sign_hash: invalid_parent_hash})

      assert_raise Ecto.InvalidChangesetError, fn ->
        insert_storage!(storage)
      end
    end

    test "signature verification works", %{user_hash: user_hash, identity: identity} do
      storage = signed_storage(identity, user_hash)
      assert Integrity.verify_signature(storage) == :ok
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
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "newer",
          owner_timestamp: timestamp
        })

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
        Repo.get_by(UserStorageVersion,
          user_hash: user_hash,
          uuid: uuid,
          sign_hash: storage1.sign_hash
        )

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
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "newer",
          owner_timestamp: timestamp
        })

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
        Repo.get_by(UserStorageVersion,
          user_hash: user_hash,
          uuid: uuid,
          sign_hash: storage2.sign_hash
        )

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
          from(v in UserStorageVersion,
            where: v.user_hash == ^user_hash and v.uuid == ^uuid
          )
        )

      assert length(versions) == 1
    end

    test "pre_apply_versioning succeeds when version already archived (report_422)", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()

      inserted =
        insert_storage!(signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"}))

      # ShapeWriter sync already archived this version
      archive_storage!(inserted)

      # HTTP ingest updates the same record — tries to archive existing again
      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: inserted.owner_timestamp + 10
        })

      changeset = newer_update_changeset(inserted, storage2)

      assert {:ok, %{update_main: updated}} =
               run_pre_apply_with_update(changeset)

      assert updated.value_b64 == "v2"
      assert count_versions(user_hash, uuid) == 1
    end

    test "pre_apply_versioning ignores already-synced older version (report_422)", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second) + 100

      insert_storage!(
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "newer",
          owner_timestamp: timestamp
        })
      )

      older =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "older",
          owner_timestamp: timestamp - 50
        })

      archive_storage_from_signed!(older)

      assert {:ok, _} = run_pre_apply(ignored_changeset(older))
      assert count_versions(user_hash, uuid) == 1
    end

    test "soft delete sets deleted_flag", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      storage1 = insert_storage!(signed_storage(identity, user_hash, %{uuid: uuid}))
      archive_storage!(storage1)

      delete_version =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          deleted_flag: true,
          parent_sign_hash: storage1.sign_hash,
          owner_timestamp: storage1.owner_timestamp + 10
        })

      storage2 =
        storage1
        |> UserStorage.update_changeset(
          Map.from_struct(delete_version)
          |> Map.take(~w(deleted_flag parent_sign_hash owner_timestamp sign_b64 sign_hash)a)
        )
        |> Repo.update!()

      assert storage2.deleted_flag == true
      assert storage2.owner_timestamp == storage1.owner_timestamp + 10
    end

    defp insert_storage!(storage) do
      %UserStorage{}
      |> UserStorage.create_changeset(Map.from_struct(storage))
      |> Repo.insert!()
    end

    defp archive_storage!(storage) do
      %UserStorageVersion{}
      |> UserStorageVersion.changeset(%{
        user_hash: storage.user_hash,
        uuid: storage.uuid,
        sign_hash: storage.sign_hash,
        value_b64: storage.value_b64,
        deleted_flag: storage.deleted_flag,
        parent_sign_hash: storage.parent_sign_hash,
        owner_timestamp: storage.owner_timestamp,
        sign_b64: storage.sign_b64
      })
      |> Repo.insert!()
    end

    defp archive_storage_from_signed!(signed) do
      signed |> Map.from_struct() |> then(&struct(UserStorage, &1)) |> archive_storage!()
    end

    defp newer_update_changeset(existing, new_storage) do
      attrs =
        new_storage
        |> Map.from_struct()
        |> Map.take(~w(value_b64 deleted_flag owner_timestamp sign_b64 sign_hash)a)
        |> Map.put(:parent_sign_hash, existing.sign_hash)

      UserStorage.update_changeset(existing, attrs)
    end

    defp ignored_changeset(storage) do
      %UserStorage{}
      |> UserStorage.create_changeset(Map.from_struct(storage))
      |> then(&%{&1 | action: :ignore})
    end

    defp run_pre_apply(changeset) do
      Ecto.Multi.new()
      |> Validation.user_storage_pre_apply_versioning(changeset, %{})
      |> Repo.transaction()
    end

    defp run_pre_apply_with_update(changeset) do
      Ecto.Multi.new()
      |> Validation.user_storage_pre_apply_versioning(changeset, %{})
      |> Ecto.Multi.update(:update_main, changeset)
      |> Repo.transaction()
    end

    defp count_versions(user_hash, uuid) do
      from(v in UserStorageVersion,
        where: v.user_hash == ^user_hash and v.uuid == ^uuid
      )
      |> Repo.aggregate(:count)
    end
  end
end

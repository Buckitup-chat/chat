defmodule Chat.Data.UserStorageVersioningTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.UserStorageFixtures

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Repo

  describe "user_storage versioning" do
    setup :user_with_card

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
      storage1 = insert_and_archive(identity, user_hash, %{uuid: uuid, value_b64: "version 1"})

      v2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "version 2",
          parent_sign_hash: storage1.sign_hash,
          owner_timestamp: storage1.owner_timestamp + 10
        })

      storage2 = apply_update!(storage1, v2)

      assert storage2.value_b64 == "version 2"
      assert storage2.owner_timestamp == storage1.owner_timestamp + 10
      assert storage2.parent_sign_hash == storage1.sign_hash

      version = get_version(user_hash, uuid, storage1.sign_hash)
      assert version != nil
      assert version.value_b64 == "version 1"
    end

    test "foreign key constraint prevents invalid parent_sign_hash", %{
      user_hash: user_hash,
      identity: identity
    } do
      storage =
        signed_storage(identity, user_hash, %{parent_sign_hash: random_storage_sign_hash()})

      assert_raise Ecto.InvalidChangesetError, fn ->
        insert_storage!(storage)
      end
    end

    test "foreign key constraint prevents invalid parent_sign_hash in user_storage_versions", %{
      user_hash: user_hash,
      identity: identity
    } do
      version =
        signed_storage(identity, user_hash, %{parent_sign_hash: random_storage_sign_hash()})

      assert_raise Ecto.InvalidChangesetError, fn ->
        archive_storage!(version)
      end
    end

    test "signature verification works", %{user_hash: user_hash, identity: identity} do
      storage = signed_storage(identity, user_hash)
      assert Integrity.verify_signature(storage) == :ok
    end

    test "soft delete sets deleted_flag", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      storage1 = insert_and_archive(identity, user_hash, %{uuid: uuid})

      delete_version =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          deleted_flag: true,
          parent_sign_hash: storage1.sign_hash,
          owner_timestamp: storage1.owner_timestamp + 10
        })

      storage2 = apply_update!(storage1, delete_version)

      assert storage2.deleted_flag == true
      assert storage2.owner_timestamp == storage1.owner_timestamp + 10
    end
  end

  defp apply_update!(existing, new_storage) do
    update_attrs =
      new_storage
      |> Map.from_struct()
      |> Map.take(~w(value_b64 deleted_flag parent_sign_hash owner_timestamp sign_b64 sign_hash)a)

    existing
    |> UserStorage.update_changeset(update_attrs)
    |> Repo.update!()
  end
end

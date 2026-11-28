defmodule Chat.Data.UserStorageVersioningConflictTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.UserStorageFixtures

  alias Chat.Data.User

  describe "user_storage conflict resolution" do
    setup :user_with_card

    test "insert_storage upserts with newer timestamp on conflict", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})
      insert_storage_via_context!(storage1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      insert_storage_via_context!(storage2)

      stored = get_storage(user_hash, uuid)
      assert stored.value_b64 == "v2"
      assert stored.owner_timestamp == storage2.owner_timestamp
    end

    test "insert_storage ignores older timestamp on conflict", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second) + 100

      insert_storage_via_context!(
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "newer",
          owner_timestamp: timestamp
        })
      )

      insert_storage_via_context!(
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "older",
          owner_timestamp: timestamp - 50
        })
      )

      stored = get_storage(user_hash, uuid)
      assert stored.value_b64 == "newer"
      assert stored.owner_timestamp == timestamp
    end

    test "insert_storage_with_conflict replaces main when newer and archives existing", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})
      inserted = insert_storage!(storage1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      assert get_storage(user_hash, uuid).value_b64 == "v2"

      version = get_version(user_hash, uuid, storage1.sign_hash)
      assert version != nil
      assert version.value_b64 == "v1"
    end

    test "insert_storage_with_conflict archives new when older and keeps existing", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      timestamp = System.system_time(:second) + 100

      inserted =
        identity
        |> signed_storage(user_hash, %{uuid: uuid, value_b64: "newer", owner_timestamp: timestamp})
        |> insert_storage!()

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "older",
          owner_timestamp: timestamp - 50
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      assert get_storage(user_hash, uuid).value_b64 == "newer"

      version = get_version(user_hash, uuid, storage2.sign_hash)
      assert version != nil
      assert version.value_b64 == "older"
    end

    test "duplicate archive insert is idempotent", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      storage1 = signed_storage(identity, user_hash, %{uuid: uuid, value_b64: "v1"})
      inserted = insert_storage!(storage1)

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: storage1.owner_timestamp + 10
        })

      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)
      {:ok, _} = User.insert_storage_with_conflict(inserted, storage2)

      assert count_versions(user_hash, uuid) == 1
    end
  end
end

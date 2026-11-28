defmodule Chat.Data.UserStorageVersioningPreApplyTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.UserStorageFixtures

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User.Validation
  alias Chat.Repo

  describe "user_storage_pre_apply_versioning (report_422)" do
    setup :user_with_card

    test "pre_apply_versioning succeeds when version already archived (report_422)", %{
      user_hash: user_hash,
      identity: identity
    } do
      uuid = Ecto.UUID.generate()
      inserted = insert_and_archive(identity, user_hash, %{uuid: uuid, value_b64: "v1"})

      storage2 =
        signed_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "v2",
          owner_timestamp: inserted.owner_timestamp + 10
        })

      assert {:ok, %{update_main: updated}} =
               run_pre_apply_with_update(newer_update_changeset(inserted, storage2))

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

      archive_storage!(older)

      assert {:ok, _} = run_pre_apply(rejected_timestamp_changeset(older))
      assert count_versions(user_hash, uuid) == 1
    end
  end

  defp newer_update_changeset(existing, new_storage) do
    attrs =
      new_storage
      |> Map.from_struct()
      |> Map.take(~w(value_b64 deleted_flag owner_timestamp sign_b64 sign_hash)a)
      |> Map.put(:parent_sign_hash, existing.sign_hash)

    UserStorage.update_changeset(existing, attrs)
  end

  defp rejected_timestamp_changeset(storage) do
    %UserStorage{}
    |> UserStorage.create_changeset(Map.from_struct(storage))
    |> Ecto.Changeset.add_error(:owner_timestamp, "timestamp not newer")
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
end

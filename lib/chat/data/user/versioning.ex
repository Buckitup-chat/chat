defmodule Chat.Data.User.Versioning do
  @moduledoc """
  Handles versioning logic for user_storage records.

  When a user_storage record is updated, the old version is archived to
  user_storage_versions and the new version replaces it in user_storage.

  This module is used by both:
  - HTTP ingestion (ElectricController)
  - Electric sync (ShapeWriter)
  """

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Schemas.UserStorageVersion
  alias Ecto.Multi

  @doc """
  Handles insert with versioning when a record with the same (user_hash, uuid) already exists.

  Compares timestamps:
  - If new timestamp > existing: archives existing to versions, inserts new to main
  - If new timestamp <= existing: inserts new to versions, keeps existing in main

  Returns {:ok, result} or {:error, reason}
  """
  def handle_insert_with_conflict(repo, existing, new_storage) do
    case new_storage.owner_timestamp > existing.owner_timestamp do
      true ->
        archive_and_insert(repo, existing, new_storage)

      false ->
        archive_changeset(new_storage)
        |> repo.insert()
    end
  end

  @doc """
  Handles update with versioning.

  Compares timestamps:
  - If new timestamp > existing: archives existing to versions, updates main
  - If new timestamp <= existing: inserts new to versions, keeps existing in main

  Returns {:ok, result} or {:error, reason}
  """
  def handle_update_with_versioning(repo, existing, new_storage) do
    case new_storage.owner_timestamp > existing.owner_timestamp do
      true ->
        archive_and_update(repo, existing, new_storage)

      false ->
        archive_changeset(new_storage)
        |> repo.insert()
    end
  end

  defp archive_and_insert(repo, existing, new_storage) do
    Multi.new()
    |> Multi.insert(:archive, archive_changeset(existing))
    |> Multi.insert(
      :update_main,
      UserStorage.create_changeset(%UserStorage{}, %{
        user_hash: new_storage.user_hash,
        uuid: new_storage.uuid,
        value_b64: new_storage.value_b64,
        deleted_flag: new_storage.deleted_flag,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_storage.owner_timestamp,
        sign_b64: new_storage.sign_b64,
        sign_hash: new_storage.sign_hash
      }),
      on_conflict: {:replace_all_except, [:user_hash, :uuid]},
      conflict_target: [:user_hash, :uuid]
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp archive_and_update(repo, existing, new_storage) do
    Multi.new()
    |> Multi.insert(:archive, archive_changeset(existing))
    |> Multi.update(
      :update_main,
      UserStorage.update_changeset(existing, %{
        value_b64: new_storage.value_b64,
        deleted_flag: new_storage.deleted_flag,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_storage.owner_timestamp,
        sign_b64: new_storage.sign_b64,
        sign_hash: new_storage.sign_hash
      })
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Creates a changeset for archiving a user_storage record to user_storage_versions.
  """
  def archive_changeset(storage) do
    UserStorageVersion.changeset(%UserStorageVersion{}, %{
      user_hash: storage.user_hash,
      uuid: storage.uuid,
      sign_hash: storage.sign_hash,
      value_b64: storage.value_b64,
      deleted_flag: storage.deleted_flag,
      parent_sign_hash: storage.parent_sign_hash,
      owner_timestamp: storage.owner_timestamp,
      sign_b64: storage.sign_b64
    })
  end
end

defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Schemas.UserStorageVersion
  alias Chat.Data.User.Validation
  alias Ecto.Multi

  def write(shape, operation, value) do
    case do_write(shape, operation, value) do
      {:ok, _} = result ->
        result

      {:error, :repo_not_available} = error ->
        log("repo not available while writing #{inspect(shape)}/#{inspect(operation)}", :warning)
        error

      {:error, {:repo_not_available, reason}} = error ->
        log(
          "repo not available while writing #{inspect(shape)}/#{inspect(operation)}: #{Exception.message(reason)}",
          :warning
        )

        error

      {:error, reason} = error ->
        log(
          "failed to write #{inspect(shape)}/#{inspect(operation)}: #{inspect(reason)}",
          :warning
        )

        error
    end
  end

  defp do_write(shape, operation, value) do
    case {shape, operation, value} do
      {:user_card, :insert, %UserCard{} = card} ->
        changeset = Validation.validate_user_card_insert(card)

        with %{valid?: true} <- changeset do
          repo().insert(changeset,
            on_conflict: {:replace_all_except, [:user_hash]},
            conflict_target: :user_hash
          )
        else
          %{valid?: false} = invalid_changeset ->
            log(
              "Invalid user_card insert signature for #{card.user_hash}: #{inspect(invalid_changeset.errors)}",
              :warning
            )

            {:ok, card}
        end

      {:user_card, :update, %UserCard{} = card} ->
        case repo().get(UserCard, card.user_hash) do
          nil ->
            {:ok, card}

          existing ->
            changeset = Validation.validate_user_card_update(existing, card)

            with %{valid?: true} <- changeset do
              repo().update(changeset)
            else
              %{valid?: false} = invalid_changeset ->
                log(
                  "Invalid user_card update signature for #{card.user_hash}: #{inspect(invalid_changeset.errors)}",
                  :warning
                )

                {:ok, card}
            end
        end

      {:user_card, :delete, %UserCard{} = card} ->
        case repo().get(UserCard, card.user_hash) do
          nil ->
            {:ok, card}

          existing ->
            changeset = Validation.validate_user_card_delete(existing, card)

            with %{valid?: true} <- changeset do
              repo().update(changeset)
            else
              %{valid?: false} = invalid_changeset ->
                log(
                  "Invalid user_card delete signature for #{card.user_hash}: #{inspect(invalid_changeset.errors)}",
                  :warning
                )

                {:ok, card}
            end
        end

      {:user_storage, :insert, %UserStorage{} = storage} ->
        handle_user_storage_insert(storage)

      {:user_storage, :update, %UserStorage{} = storage} ->
        handle_user_storage_update(storage)
    end
  rescue
    e in RuntimeError -> {:error, {:repo_not_available, e}}
    e in Postgrex.Error -> {:error, e}
  end

  defp handle_user_storage_insert(storage) do
    # Verify parent user_card exists
    with parent when not is_nil(parent) <- repo().get(UserCard, storage.user_hash),
         storage_with_hash <- calculate_sign_hash(storage),
         changeset <- Validation.validate_user_storage_insert(storage_with_hash),
         %{valid?: true} <- changeset do
      # Check if record already exists
      case repo().get_by(UserStorage, user_hash: storage.user_hash, uuid: storage.uuid) do
        nil ->
          # No conflict - insert directly
          repo().insert(changeset)

        existing ->
          # Conflict - compare timestamps
          compare_and_version_insert(existing, storage_with_hash)
      end
    else
      nil ->
        log(
          "Skipping user_storage insert - parent user_card not yet synced (user_hash: #{storage.user_hash})",
          :debug
        )

        {:ok, :skipped_no_parent}

      %{valid?: false} = invalid_changeset ->
        log(
          "Invalid user_storage insert signature: #{inspect(invalid_changeset.errors)}",
          :warning
        )

        {:ok, storage}
    end
  end

  defp handle_user_storage_update(storage) do
    # Verify parent user_card exists
    with {_, parent} when not is_nil(parent) <-
           {:parent, repo().get(UserCard, storage.user_hash)},
         {_, existing} when not is_nil(existing) <-
           {:existing, repo().get_by(UserStorage, user_hash: storage.user_hash, uuid: storage.uuid)},
         storage_with_hash <- calculate_sign_hash(storage),
         changeset <- Validation.validate_user_storage_update(existing, storage_with_hash),
         %{valid?: true} <- changeset do
      # Compare timestamps and version
      compare_and_version_update(existing, storage_with_hash)
    else
      {:parent, nil} ->
        log(
          "Skipping user_storage update - parent user_card not found (user_hash: #{storage.user_hash})",
          :debug
        )

        {:ok, :skipped_no_parent}

      {:existing, nil} ->
        {:ok, storage}

      %{valid?: false} = invalid_changeset ->
        log(
          "Invalid user_storage update signature: #{inspect(invalid_changeset.errors)}",
          :warning
        )

        {:ok, storage}
    end
  end

  defp compare_and_version_insert(existing, new_storage) do
    if new_storage.owner_timestamp > existing.owner_timestamp do
      # New version is newer - archive existing to versions, insert new to main
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
      |> repo().transaction()
      |> case do
        {:ok, %{update_main: result}} -> {:ok, result}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      # New version is older - insert to versions, keep existing in main
      archive_changeset(new_storage)
      |> repo().insert()
    end
  end

  defp compare_and_version_update(existing, new_storage) do
    if new_storage.owner_timestamp > existing.owner_timestamp do
      # New version is newer - archive existing to versions, update main
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
      |> repo().transaction()
      |> case do
        {:ok, %{update_main: result}} -> {:ok, result}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      # New version is older - insert to versions, keep existing in main
      archive_changeset(new_storage)
      |> repo().insert()
    end
  end

  defp calculate_sign_hash(%UserStorage{sign_b64: sign_b64} = storage) when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> Chat.Data.Types.UserStorageSignHash.from_binary()

    %{storage | sign_hash: sign_hash}
  end

  defp calculate_sign_hash(storage), do: storage

  defp archive_changeset(storage) do
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

defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User.Validation

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
              "Invalid user_card insert signature for #{Base.encode16(card.user_hash, case: :lower)}: #{inspect(invalid_changeset.errors)}",
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
                  "Invalid user_card update signature for #{Base.encode16(card.user_hash, case: :lower)}: #{inspect(invalid_changeset.errors)}",
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
                  "Invalid user_card delete signature for #{Base.encode16(card.user_hash, case: :lower)}: #{inspect(invalid_changeset.errors)}",
                  :warning
                )

                {:ok, card}
            end
        end

      {:user_storage, :insert, %UserStorage{} = storage} ->
        # Verify parent user_card exists - required for data integrity
        with parent when not is_nil(parent) <- repo().get(UserCard, storage.user_hash),
             changeset <- UserStorage.create_changeset(%UserStorage{}, Map.from_struct(storage)),
             %{valid?: true} <- changeset do
          repo().insert(changeset,
            on_conflict: {:replace, [:value_b64]},
            conflict_target: [:user_hash, :uuid]
          )
        else
          nil ->
            # Parent not synced yet - skip this record
            # Electric live sync will re-deliver it once parent exists
            log(
              "Skipping user_storage insert - parent user_card not yet synced (user_hash: #{Base.encode16(storage.user_hash, case: :lower)})",
              :debug
            )

            {:ok, :skipped_no_parent}

          _invalid ->
            {:ok, storage}
        end

      {:user_storage, :update, %UserStorage{} = storage} ->
        # Verify parent user_card exists before updating
        with {_, parent} when not is_nil(parent) <-
               {:parent, repo().get(UserCard, storage.user_hash)},
             {_, existing} when not is_nil(existing) <-
               {:existing,
                repo().get_by(UserStorage, user_hash: storage.user_hash, uuid: storage.uuid)} do
          attrs =
            storage
            |> Map.take([:value_b64])
            |> Map.reject(fn {_k, v} -> is_nil(v) end)

          existing
          |> UserStorage.update_changeset(attrs)
          |> repo().update()
        else
          {:parent, nil} ->
            # Parent doesn't exist or was deleted - skip update
            log(
              "Skipping user_storage update - parent user_card not found (user_hash: #{Base.encode16(storage.user_hash, case: :lower)})",
              :debug
            )

            {:ok, :skipped_no_parent}

          {:existing, nil} ->
            {:ok, storage}
        end

      {:user_storage, :delete, %UserStorage{user_hash: user_hash, uuid: uuid}} ->
        repo().delete(%UserStorage{user_hash: user_hash, uuid: uuid}, allow_stale: true)
    end
  rescue
    e in RuntimeError -> {:error, {:repo_not_available, e}}
    e in Postgrex.Error -> {:error, e}
  end
end

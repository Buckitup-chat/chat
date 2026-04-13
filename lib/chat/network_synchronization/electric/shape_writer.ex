defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User
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
          User.upsert_card(changeset)
        else
          %{valid?: false} = invalid_changeset ->
            log(
              "Invalid user_card insert signature for #{card.user_hash}: #{inspect(invalid_changeset.errors)}",
              :warning
            )

            {:ok, card}
        end

      {:user_card, :update, %UserCard{} = card} ->
        case User.get_card(card.user_hash) do
          nil ->
            {:ok, card}

          existing ->
            changeset = Validation.validate_user_card_update(existing, card)

            with %{valid?: true} <- changeset do
              User.update_card(changeset)
            else
              %{valid?: false, action: :ignore} ->
                {:ok, card}

              %{valid?: false} = invalid_changeset ->
                log(
                  "Invalid user_card update signature for #{card.user_hash}: #{inspect(invalid_changeset.errors)}",
                  :warning
                )

                {:ok, card}
            end
        end

      {:user_card, :delete, %UserCard{} = card} ->
        case User.get_card(card.user_hash) do
          nil ->
            {:ok, card}

          existing ->
            changeset = Validation.validate_user_card_delete(existing, card)

            with %{valid?: true} <- changeset do
              User.update_card(changeset)
            else
              %{valid?: false, action: :ignore} ->
                {:ok, card}

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
    with parent when not is_nil(parent) <- User.get_card(storage.user_hash),
         storage_with_hash <- calculate_sign_hash(storage),
         changeset <- Validation.validate_user_storage_insert(storage_with_hash),
         %{valid?: true} <- changeset do
      # Check if record already exists
      case User.get_storage(storage.user_hash, storage.uuid) do
        nil ->
          User.insert_storage(changeset)

        existing ->
          User.insert_storage_with_conflict(existing, storage_with_hash)
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
           {:parent, User.get_card(storage.user_hash)},
         {_, existing} when not is_nil(existing) <-
           {:existing, User.get_storage(storage.user_hash, storage.uuid)},
         storage_with_hash <- calculate_sign_hash(storage),
         changeset <- Validation.validate_user_storage_update(existing, storage_with_hash),
         %{valid?: true} <- changeset do
      User.update_storage_with_versioning(existing, storage_with_hash)
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

  defp calculate_sign_hash(%UserStorage{sign_b64: sign_b64} = storage) when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> Chat.Data.Types.UserStorageSignHash.from_binary()

    %{storage | sign_hash: sign_hash}
  end

  defp calculate_sign_hash(storage), do: storage
end

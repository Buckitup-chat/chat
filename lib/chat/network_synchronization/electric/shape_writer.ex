defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage

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
        %UserCard{}
        |> UserCard.create_changeset(Map.from_struct(card))
        |> case do
          %{valid?: true} = changeset ->
            repo().insert(changeset,
              on_conflict: {:replace_all_except, [:user_hash]},
              conflict_target: :user_hash
            )

          _invalid ->
            {:ok, card}
        end

      {:user_card, :update, %UserCard{} = card} ->
        case repo().get(UserCard, card.user_hash) do
          nil ->
            {:ok, card}

          existing ->
            attrs =
              card
              |> Map.take([:name])
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            existing
            |> UserCard.update_name_changeset(attrs)
            |> repo().update()
        end

      {:user_card, :delete, %UserCard{user_hash: user_hash}} ->
        repo().delete(%UserCard{user_hash: user_hash}, allow_stale: true)

      {:user_storage, :insert, %UserStorage{} = storage} ->
        %UserStorage{}
        |> UserStorage.create_changeset(Map.from_struct(storage))
        |> case do
          %{valid?: true} = changeset ->
            repo().insert(changeset,
              on_conflict: {:replace, [:value_b64]},
              conflict_target: [:user_hash, :uuid]
            )

          _invalid ->
            {:ok, storage}
        end

      {:user_storage, :update, %UserStorage{} = storage} ->
        case repo().get_by(UserStorage, user_hash: storage.user_hash, uuid: storage.uuid) do
          nil ->
            {:ok, storage}

          existing ->
            attrs =
              storage
              |> Map.take([:value_b64])
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            existing
            |> UserStorage.update_changeset(attrs)
            |> repo().update()
        end

      {:user_storage, :delete, %UserStorage{user_hash: user_hash, uuid: uuid}} ->
        repo().delete(%UserStorage{user_hash: user_hash, uuid: uuid}, allow_stale: true)
    end
  rescue
    e in RuntimeError -> {:error, {:repo_not_available, e}}
    e in Postgrex.Error -> {:error, e}
  end
end

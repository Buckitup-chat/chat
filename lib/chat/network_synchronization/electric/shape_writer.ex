defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  require Logger

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage

  def write(shape, operation, value) do
    case do_write(shape, operation, value) do
      {:ok, _} = result ->
        result

      {:error, :repo_not_available} = error ->
        error

      {:error, reason} = error ->
        Logger.warning(
          "ShapeWriter: failed to write #{inspect(shape)}/#{inspect(operation)}: #{inspect(reason)}"
        )

        error
    end
  end

  defp do_write(shape, operation, value) do
    try do
      case {shape, operation, value} do
        {:user_card, op, %UserCard{} = card} when op in [:insert, :update] ->
          repo().insert(card,
            on_conflict: {:replace_all_except, [:user_hash]},
            conflict_target: :user_hash
          )

        {:user_card, :delete, %UserCard{user_hash: user_hash}} ->
          repo().delete(%UserCard{user_hash: user_hash}, allow_stale: true)

        {:user_storage, op, %UserStorage{} = storage} when op in [:insert, :update] ->
          repo().insert(storage,
            on_conflict: {:replace, [:value_b64]},
            conflict_target: [:user_hash, :uuid]
          )

        {:user_storage, :delete, %UserStorage{user_hash: user_hash, uuid: uuid}} ->
          repo().delete(%UserStorage{user_hash: user_hash, uuid: uuid}, allow_stale: true)
      end
    rescue
      RuntimeError -> {:error, :repo_not_available}
    end
  end
end

defmodule Chat.Data.Shapes.UserStorage do
  @moduledoc "Shape behaviour implementation for user_storage"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Schemas.UserStorageVersion
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.Data.User.Validation
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :user_storage

  @impl true
  def schema_module, do: UserStorage

  @impl true
  def versions_schema, do: UserStorageVersion

  @impl true
  def sync_required_parents(_op, %{user_hash: hash}), do: [{:user_card, hash}]

  @impl true
  def sync_derive_fields(%UserStorage{sign_b64: sign_b64} = storage) do
    case sign_b64 do
      bin when is_binary(bin) ->
        sign_hash =
          bin
          |> EnigmaPq.hash()
          |> UserStorageSignHash.from_binary()

        %{storage | sign_hash: sign_hash}

      _ ->
        storage
    end
  end

  @impl true
  def sync_persist(operation, storage) do
    case operation do
      :insert ->
        storage
        |> Validation.validate_user_storage_insert()
        |> persist_insert(storage)

      :update ->
        persist_update(storage)
    end
  end

  defp persist_insert(changeset, storage) do
    case changeset do
      %{valid?: true} ->
        upsert_storage(changeset, storage)

      %{valid?: false} = invalid_changeset ->
        log(
          "Invalid user_storage insert signature: #{inspect(invalid_changeset.errors)}",
          :warning
        )

        {:ok, storage}
    end
  end

  defp upsert_storage(changeset, storage) do
    case User.get_storage(storage.user_hash, storage.uuid) do
      nil -> User.insert_storage(changeset)
      existing -> User.insert_storage_with_conflict(existing, storage)
    end
  end

  defp persist_update(storage) do
    with existing when not is_nil(existing) <- User.get_storage(storage.user_hash, storage.uuid),
         %{valid?: true} <- Validation.validate_user_storage_update(existing, storage) do
      User.update_storage_with_versioning(existing, storage)
    else
      nil ->
        {:ok, storage}

      %{valid?: false} = invalid_changeset ->
        log(
          "Invalid user_storage update signature: #{inspect(invalid_changeset.errors)}",
          :warning
        )

        {:ok, storage}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, UserStorage,
      accept: [:insert, :update],
      check: &Validation.user_storage_allowed(&1, user_pop_context),
      validate: &Validation.user_storage_validate_with_versioning/3,
      insert: [
        pre_apply: &Validation.user_storage_pre_apply_versioning/3
      ],
      update: [
        pre_apply: &Validation.user_storage_pre_apply_versioning/3
      ]
    )
  end
end

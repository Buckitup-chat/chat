defmodule Chat.Data.Schemas.UserStorage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @max_value_size 10_485_760

  schema "user_storage" do
    field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
    field(:uuid, Ecto.UUID, primary_key: true)
    field(:value_b64, :binary)
    field(:deleted_flag, :boolean)
    field(:parent_sign_hash, Chat.Data.Types.UserStorageSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, Chat.Data.Types.UserStorageSignHash)

    belongs_to :parent_version, Chat.Data.Schemas.UserStorageVersion,
      foreign_key: :parent_sign_hash,
      references: :sign_hash,
      type: Chat.Data.Types.UserStorageSignHash,
      define_field: false
  end

  def create_changeset(storage, attrs) do
    storage
    |> cast(attrs, [
      :user_hash,
      :uuid,
      :value_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ])
    |> validate_required([
      :user_hash,
      :uuid,
      :value_b64,
      :deleted_flag,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ])
    |> validate_value_size()
    |> unique_constraint([:user_hash, :uuid], name: :user_storage_pkey)
    |> foreign_key_constraint(:parent_sign_hash, name: :user_storage_parent_sign_hash_fkey)
  end

  def update_changeset(storage, attrs) do
    storage
    |> cast(attrs, [
      :value_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ])
    |> validate_required([
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ])
    |> validate_value_size()
    |> foreign_key_constraint(:parent_sign_hash, name: :user_storage_parent_sign_hash_fkey)
  end

  defp validate_value_size(changeset) do
    case get_field(changeset, :value_b64) do
      nil ->
        changeset

      value when byte_size(value) <= @max_value_size ->
        changeset

      _ ->
        add_error(changeset, :value_b64, "exceeds 10 MB limit")
    end
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(storage) do
      storage
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :parent_version, :__meta__])
    end

    def signing_key(storage) do
      User.get_card(storage.user_hash).sign_pkey
    end

    def signature(storage), do: storage.sign_b64
  end
end

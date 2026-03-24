defmodule Chat.Data.Schemas.UserStorageVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "user_storage_versions" do
    field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
    field(:uuid, Ecto.UUID, primary_key: true)
    field(:sign_hash, Chat.Data.Types.UserStorageSignHash, primary_key: true)
    field(:value_b64, :binary)
    field(:deleted_flag, :boolean)
    field(:parent_sign_hash, Chat.Data.Types.UserStorageSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)

    belongs_to :parent_version, Chat.Data.Schemas.UserStorageVersion,
      foreign_key: :parent_sign_hash,
      references: :sign_hash,
      type: Chat.Data.Types.UserStorageSignHash,
      define_field: false

    has_many :child_versions, Chat.Data.Schemas.UserStorageVersion,
      foreign_key: :parent_sign_hash,
      references: :sign_hash
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :user_hash,
      :uuid,
      :sign_hash,
      :value_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64
    ])
    |> validate_required([
      :user_hash,
      :uuid,
      :sign_hash,
      :value_b64,
      :deleted_flag,
      :owner_timestamp,
      :sign_b64
    ])
  end
end

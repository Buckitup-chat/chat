defmodule Chat.Data.Schemas.Origin do
  @moduledoc "Ecto schema for origin entities (businesses, venues) with their own PQ identity."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key {:origin_hash, UserHash, []}

  @create_fields [
    :origin_hash,
    :owner_hash,
    :owner_cert,
    :name,
    :moderation_mode,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required @create_fields

  @update_fields [
    :name,
    :moderation_mode,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  schema "origins" do
    field(:owner_hash, UserHash)
    field(:owner_cert, :binary)
    field(:name, :string)
    field(:moderation_mode, Ecto.Enum, values: [:none, :post, :pre])
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, OriginSignHash)
  end

  def create_changeset(origin, attrs) do
    origin
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:origin_hash, name: :origins_pkey)
  end

  def update_changeset(origin, attrs) do
    origin
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(origin) do
      origin
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(origin), do: User.get_card(origin.origin_hash).sign_pkey

    def signature(origin), do: origin.sign_b64
  end
end

defmodule Chat.Data.Schemas.UserCard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_hash, Chat.Data.Types.UserHash, []}
  @create_fields [
    :user_hash,
    :sign_pkey,
    :contact_pkey,
    :contact_cert,
    :crypt_pkey,
    :crypt_cert,
    :name,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required_fields @create_fields
  @update_name_fields [:name, :owner_timestamp, :sign_b64]
  @update_deleted_flag_fields [:deleted_flag, :owner_timestamp, :sign_b64]

  schema "user_cards" do
    field(:sign_pkey, :binary)
    field(:contact_pkey, :binary)
    field(:contact_cert, :binary)
    field(:crypt_pkey, :binary)
    field(:crypt_cert, :binary)
    field(:name, :string)
    field(:deleted_flag, :boolean)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(card, attrs) do
    card
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required_fields)
    |> unique_constraint(:user_hash, name: :user_cards_pkey)
  end

  def update_name_changeset(card, attrs) do
    card
    |> cast(attrs, @update_name_fields)
    |> validate_required(@update_name_fields)
  end

  def update_deleted_flag_changeset(card, attrs) do
    card
    |> cast(attrs, @update_deleted_flag_fields)
    |> validate_required(@update_deleted_flag_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(card) do
      card
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(card), do: card.sign_pkey

    def signature(card), do: card.sign_b64
  end

  defimpl Enigma.Hash.Protocol, for: __MODULE__ do
    def to_iodata(user_card), do: user_card.user_hash
  end
end

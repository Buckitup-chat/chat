defmodule Chat.Data.Schemas.UserCard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_hash, Chat.Data.Types.UserHash, []}

  schema "user_cards" do
    field(:sign_pkey, :binary)
    field(:contact_pkey, :binary)
    field(:contact_cert, :binary)
    field(:crypt_pkey, :binary)
    field(:crypt_cert, :binary)
    field(:name, :string)
  end

  def create_changeset(card, attrs) do
    card
    |> cast(attrs, [
      :user_hash,
      :sign_pkey,
      :contact_pkey,
      :contact_cert,
      :crypt_pkey,
      :crypt_cert,
      :name
    ])
    |> validate_required([
      :user_hash,
      :sign_pkey,
      :contact_pkey,
      :contact_cert,
      :crypt_pkey,
      :crypt_cert,
      :name
    ])
    |> unique_constraint(:user_hash, name: :user_cards_pkey)
  end

  def update_name_changeset(card, attrs) do
    card
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end

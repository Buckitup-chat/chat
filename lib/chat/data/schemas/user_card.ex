defmodule Chat.Data.Schemas.UserCard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_hash, Chat.Data.Types.UserHash, []}

  schema "user_cards" do
    field(:sign_pkey, :binary)
    field(:crypt_pkey, :binary)
    field(:crypt_pkey_cert, :binary)
    field(:name, :string) # :text in DB, :string in Ecto
  end

  def create_changeset(card, attrs) do
    card
    |> cast(attrs, [:user_hash, :sign_pkey, :crypt_pkey, :crypt_pkey_cert, :name])
    |> validate_required([:user_hash, :sign_pkey, :crypt_pkey, :crypt_pkey_cert, :name])
  end

  def update_name_changeset(card, attrs) do
    card
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end

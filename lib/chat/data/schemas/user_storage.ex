defmodule Chat.Data.Schemas.UserStorage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "user_storage" do
    field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
    field(:uuid, Ecto.UUID, primary_key: true)
    field(:value, :binary)
  end

  def changeset(storage, attrs) do
    storage
    |> cast(attrs, [:user_hash, :uuid, :value])
    |> validate_required([:user_hash, :uuid, :value])
  end
end

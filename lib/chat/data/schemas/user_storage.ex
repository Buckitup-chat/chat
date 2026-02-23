defmodule Chat.Data.Schemas.UserStorage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @max_value_size 10_485_760

  schema "user_storage" do
    field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
    field(:uuid, Ecto.UUID, primary_key: true)
    field(:value_b64, :binary)
  end

  def create_changeset(storage, attrs) do
    storage
    |> cast(attrs, [:user_hash, :uuid, :value_b64])
    |> validate_required([:user_hash, :uuid, :value_b64])
    |> validate_value_size()
    |> unique_constraint([:user_hash, :uuid], name: :user_storage_pkey)
  end

  def update_changeset(storage, attrs) do
    storage
    |> cast(attrs, [:value_b64])
    |> validate_required([:value_b64])
    |> validate_value_size()
  end

  def delete_changeset(storage, _attrs), do: storage

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
end

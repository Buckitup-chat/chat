defmodule Chat.Data.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:pub_key, :binary, []}
  @timestamps_opts [type: :utc_datetime]

  schema "users" do
    field :name, :string
    field :hash, :string, virtual: true

    # Explicitly disable timestamps since they were removed in migration
    timestamps(inserted_at: false, updated_at: false)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :pub_key])
    |> validate_required([:name, :pub_key])
    |> unique_constraint(:pub_key)
  end

  @doc """
  Creates an Ecto schema from a Chat.Card struct
  """
  def from_card(%Chat.Card{} = card) do
    %__MODULE__{
      name: card.name,
      pub_key: card.pub_key
    }
  end

  @doc """
  Converts an Ecto schema to a Chat.Card struct
  """
  def to_card(%__MODULE__{} = user) do
    Chat.Card.new(user.name, user.pub_key)
  end

  defimpl Enigma.Hash.Protocol, for: __MODULE__ do
    def to_iodata(user), do: user.pub_key
  end

  # Access behavior implementation
  def fetch(user, :hash) do
    {:ok, Enigma.Hash.short_hash(user.pub_key)}
  end

  def fetch(user, key) do
    Map.fetch(user, key)
  end

  def get(user, key, default \\ nil) do
    case fetch(user, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def get_and_update(user, key, fun) do
    case fetch(user, key) do
      {:ok, value} ->
        {get, update} = fun.(value)
        {get, Map.put(user, key, update)}
      :error ->
        {get, update} = fun.(nil)
        {get, Map.put(user, key, update)}
    end
  end

  def pop(user, key, default \\ nil) do
    value = get(user, key, default)
    {value, Map.delete(user, key)}
  end
end

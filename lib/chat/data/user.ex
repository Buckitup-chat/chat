defmodule Chat.Data.User do
  @moduledoc """
  User context for managing user data in Postgres
  """

  alias Chat.Card
  alias Chat.Data.Queries.UserQueries
  alias Chat.Identity

  @doc """
  Registers a user from an Identity or Card
  """
  def register(%Identity{} = identity) do
    identity |> Card.from_identity() |> register()
  end

  def register(%Card{} = card) do
    UserQueries.insert_card(card)
    card.pub_key
  end

  @doc """
  Gets all users from Postgres
  """
  def all do
    UserQueries.list_all()
    |> Map.new(fn user -> {user.pub_key, Chat.Data.Schemas.User.to_card(user)} end)
  end

  @doc """
  Gets a user by public key from Postgres
  """
  def get(pub_key) do
    case UserQueries.get_by_pub_key(pub_key) do
      nil -> nil
      user -> Chat.Data.Schemas.User.to_card(user)
    end
  end

  @doc """
  Removes a user by public key from Postgres
  """
  def remove(pub_key) do
    UserQueries.delete_by_pub_key(pub_key)
  end

  @doc """
  Legacy function maintained for compatibility.
  In Postgres-only mode, no need to wait for writes.
  """
  def await_saved(_) do
    :ok
  end

  @doc """
  Creates a user directly in Postgres.
  Electric will automatically detect and sync the change.
  """
  def create(attrs) do
    alias Chat.Data.Schemas.User

    changeset = User.changeset(%User{}, attrs)
    Chat.Repo.insert(changeset)
  end
end

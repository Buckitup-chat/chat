defmodule Chat.Data.Queries.UserQueries do
  @moduledoc """
  Database operations for user records
  """
  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.User
  alias Chat.Card

  @on_conflict_fields [:name]
  @conflict_target :pub_key

  @doc """
  Inserts or updates a user with conflict handling on pub_key
  """
  def insert_or_update(%User{} = user) do
    repo().insert(user,
      on_conflict: {:replace, @on_conflict_fields},
      conflict_target: @conflict_target
    )
  end

  @doc """
  Inserts a Card as a user with conflict handling
  """
  def insert_card(%Card{} = card) do
    card
    |> User.from_card()
    |> insert_or_update()
  end

  @doc """
  Creates a user from raw attributes.

  This is used when Electric or other parts of the system
  need to insert a user directly into Postgres.
  """
  def create(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Gets a user by public key
  """
  def get_by_pub_key(pub_key) do
    repo().get(User, pub_key)
  end

  @doc """
  Lists all users
  """
  def list_all do
    repo().all(User)
  end

  @doc """
  Deletes a user by public key
  """
  def delete_by_pub_key(pub_key) do
    case get_by_pub_key(pub_key) do
      nil -> {:error, :not_found}
      user -> repo().delete(user)
    end
  end
end

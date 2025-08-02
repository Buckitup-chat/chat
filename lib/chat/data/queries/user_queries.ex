defmodule Chat.Data.Queries.UserQueries do
  @moduledoc """
  Database operations for user records
  """

  alias Chat.Repo
  alias Chat.Data.Schemas.User
  alias Chat.Card

  @on_conflict_fields [:name]
  @conflict_target :pub_key

  @doc """
  Inserts or updates a user with conflict handling on pub_key
  """
  def insert_or_update(%User{} = user) do
    Repo.insert(user,
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
  Gets a user by public key
  """
  def get_by_pub_key(pub_key) do
    Repo.get(User, pub_key)
  end

  @doc """
  Lists all users
  """
  def list_all do
    Repo.all(User)
  end

  @doc """
  Deletes a user by public key
  """
  def delete_by_pub_key(pub_key) do
    case get_by_pub_key(pub_key) do
      nil -> {:error, :not_found}
      user -> Repo.delete(user)
    end
  end
end

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
    # Save to Postgres using Ecto with conflict handling
    UserQueries.insert_card(card)

    card.pub_key
  end

  @doc """
  Gets all users from Postgres
  """
  def all do
    UserQueries.list_all()
    |> Enum.map(fn user -> {user.pub_key, Chat.Data.Schemas.User.to_card(user)} end)
    |> Enum.into(%{})
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
  def await_saved(pub_key_list) when is_list(pub_key_list) do
    :ok
  end

  def await_saved(_pub_key) do
    :ok
  end
end

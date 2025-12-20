defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Data.User

  @doc """
  Registers a user from an Identity or Card
  """
  def enlist(%Identity{} = identity) do
    User.register(identity)
  end

  def enlist(%Card{} = card) do
    User.register(card)
  end

  @doc """
  Gets all users
  """
  def all do
    User.all()
  end

  @doc """
  Gets a user by public key
  """
  def one(pub_key) do
    User.get(pub_key)
  end

  @doc """
  Removes a user by public key
  """
  def remove(pub_key) do
    User.remove(pub_key)
  end

  @doc """
  Waits for users to be written to storage
  """
  def await_saved(pub_key_list) when is_list(pub_key_list) do
    User.await_saved(pub_key_list)
  end

  def await_saved(pub_key) do
    User.await_saved(pub_key)
  end
end

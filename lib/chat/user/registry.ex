defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  alias Chat.Card
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Identity

  def enlist(%Identity{} = user) do
    card = user |> Card.from_identity()

    Db.put({:users, card.pub_key}, card)

    card.pub_key
  end

  def all do
    {{:users, 0}, {:"users\0", 0}}
    |> Db.list(fn {{:users, pub_key}, %Card{} = user} -> {pub_key, user} end)
  end

  def remove(pub_key) do
    Db.delete({:users, pub_key})
  end

  def await_saved(pub_key) do
    ChangeTracker.await({:users, pub_key})
  end
end

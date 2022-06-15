defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  alias Chat.Card
  alias Chat.Db
  alias Chat.Identity
  alias Chat.Utils

  def enlist(%Identity{} = user) do
    card = user |> Card.from_identity()
    hash = card.pub_key |> Utils.hash()

    Db.put({:users, hash}, card)

    hash
  end

  def all do
    {{:users, 0}, {:"users\0", 0}}
    |> Db.list(fn {{:users, hash}, %Card{} = user} -> {hash, user} end)
  end

  def remove(hash) do
    Db.delete({:users, hash})
  end
end

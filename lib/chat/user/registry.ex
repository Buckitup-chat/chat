defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  alias Chat.Card
  alias Chat.Db
  alias Chat.Db.Copying
  alias Chat.Identity

  def enlist(%Identity{} = user) do
    user |> Card.from_identity() |> enlist()
  end

  def enlist(%Card{} = card) do
    Db.put({:users, card.pub_key}, card)

    card.pub_key
  end

  def all do
    {{:users, 0}, {:"users\0", 0}}
    |> Db.list(fn {{:users, pub_key}, %Card{} = user} -> {pub_key, user} end)
  end

  def one(pub_key) do
    Db.get({:users, pub_key})
  end

  def remove(pub_key) do
    Db.delete({:users, pub_key})
  end

  def await_saved(pub_key_list) when is_list(pub_key_list) do
    pub_key_list
    |> Enum.map(&{:users, &1})
    |> Copying.await_written_into(Db.db())
  end

  def await_saved(pub_key) do
    Copying.await_written_into([{:users, pub_key}], Db.db())
  end
end

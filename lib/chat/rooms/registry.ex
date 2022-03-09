defmodule Chat.Rooms.Registry do
  @moduledoc "Holds all rooms"

  alias Chat.Card
  alias Chat.Db
  alias Chat.Rooms.Room
  alias Chat.Utils

  def find(%Card{pub_key: pub_key}), do: pub_key |> Utils.hash() |> find()
  def find(hash), do: Db.db() |> CubDB.get({:rooms, hash})

  def all,
    do:
      {{:rooms, 0}, {:"rooms\0", 0}}
      |> Db.list(fn {{:rooms, hash}, %Room{} = room} -> {hash, room} end)

  def update(%Room{pub_key: pub_key} = room) do
    Db.db()
    |> CubDB.put({:rooms, pub_key |> Utils.hash()}, room)
  end
end

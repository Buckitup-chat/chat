defmodule Chat.Rooms.Registry do
  @moduledoc "Holds all rooms"

  alias Chat.Db.ChangeTracker
  alias Chat.Db
  alias Chat.Rooms.Room
  alias Chat.Utils

  def find(hash), do: Db.get({:rooms, hash})

  def all,
    do:
      {{:rooms, 0}, {:"rooms\0", 0}}
      |> Db.list(fn {{:rooms, hash}, %Room{} = room} -> {hash, room} end)

  def update(%Room{pub_key: pub_key} = room) do
    Db.put({:rooms, pub_key |> Utils.hash()}, room)

    room
  end

  def await_saved(hash), do: ChangeTracker.await({:rooms, hash})

  def delete(hash), do: Db.delete({:rooms, hash})
end

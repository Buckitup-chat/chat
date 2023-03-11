defmodule Chat.Rooms.Registry do
  @moduledoc "Holds all rooms"

  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Rooms.Room

  def find(room_public_key), do: Db.get({:rooms, room_public_key})

  def all,
    do:
      {{:rooms, 0}, {:"rooms\0", 0}}
      |> Db.list(fn {{:rooms, room_public_key}, %Room{} = room} -> {room_public_key, room} end)

  def update(%Room{pub_key: pub_key} = room) do
    Db.put({:rooms, pub_key}, room)

    room
  end

  def await_saved(room_public_key), do: ChangeTracker.await({:rooms, room_public_key})

  def delete(room_public_key), do: Db.delete({:rooms, room_public_key})
end

defmodule Chat.Rooms do
  @moduledoc "Rooms context"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Rooms.Registry
  alias Chat.Rooms.Room
  alias Chat.Utils

  @doc "Returns new room Identity"
  def add(me, name) do
    name
    |> Identity.create()
    |> tap(fn room_identity ->
      Room.create(me, room_identity)
      |> Registry.update()
    end)
  end

  @doc "Returns room Cards {my_rooms, available_rooms}"
  def list(my_rooms) do
    my_room_hashes =
      my_rooms
      |> Enum.map(
        &(&1
          |> Identity.pub_key()
          |> Utils.hash())
      )

    Registry.all()
    |> Map.values()
    |> Enum.map(&%Card{name: &1.name, pub_key: &1.pub_key, hash: Utils.hash(&1.pub_key)})
    |> Enum.sort_by(& &1.name)
    |> Enum.split_with(&(&1.hash in my_room_hashes))
  end

  @doc "Returns Room or nil"
  def get(hash) do
    Registry.find(hash)
  end

  defdelegate add_text(room, me, text), to: Room
  defdelegate add_image(room, me, data), to: Room
  defdelegate glimpse(room), to: Room

  defdelegate read(
                room,
                room_identity,
                before \\ DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix(),
                amount \\ 1000
              ),
              to: Room

  defdelegate update(room), to: Registry
end

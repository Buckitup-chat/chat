defmodule Chat.Rooms do
  @moduledoc "Rooms context"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Rooms.Registry
  alias Chat.Rooms.Room
  alias Chat.Utils

  @doc "Returns new room Identity"
  @spec add(me :: Identity, name :: String) :: Identity
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
    |> Enum.map(&%Card{name: &1.card, pub_key: &1.pub_key, hash: Utils.hash(&1.pub_key)})
    |> Enum.sort_by(& &1.name)
    |> Enum.split_with(&(&1.hash in my_room_hashes))
  end
end

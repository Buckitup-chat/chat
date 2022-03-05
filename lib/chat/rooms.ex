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

  def add_request(room_hash, user_identity) do
    room_hash
    |> get()
    |> Room.add_request(user_identity)
    |> update()
  end

  def approve_requests(room_hash, room_identity) do
    room = get(room_hash)

    if room do
      room
      |> Room.approve_requests(room_identity)
      |> update()
    end
  end

  def join_approved_requests(room_hash, person_identity) do
    room_hash
    |> get
    |> Room.join_approved_requests(person_identity)
    |> then(fn {room, joined_identities} ->
      update(room)

      joined_identities
    end)
  end

  def is_requested_by?(room_hash, person_hash) do
    room_hash
    |> get()
    |> Room.is_requested_by?(person_hash)
  end

  defdelegate update(room), to: Registry
end

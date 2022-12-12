defmodule Chat.Rooms do
  @moduledoc "Rooms context"

  alias Chat.Identity
  alias Chat.Log
  alias Chat.Messages
  alias Chat.Rooms.Message
  alias Chat.Rooms.Registry
  alias Chat.Rooms.Room
  alias Chat.Rooms.RoomMessages
  alias Chat.Utils

  @doc "Returns new room Identity"
  def add(me, name, type \\ :public) do
    name
    |> Identity.create()
    |> tap(fn room_identity ->
      Room.create(me, room_identity, type)
      |> Registry.update()
    end)
  end

  @doc "Returns room Cards {my_rooms, available_rooms}"
  def list(my_rooms) do
    my_room_hashes =
      my_rooms
      |> Enum.map(&Utils.hash/1)
      |> MapSet.new()

    Registry.all()
    |> Map.filter(fn {hash, room} ->
      room.type in [:public, :request] or MapSet.member?(my_room_hashes, hash)
    end)
    |> Enum.map(fn {hash, room} ->
      %{name: room.name, pub_key: room.pub_key, hash: hash, type: room.type}
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.split_with(&MapSet.member?(my_room_hashes, &1.hash))
  end

  @doc "Returns Room or nil"
  def get(hash) do
    Registry.find(hash)
  end

  def delete(hash) do
    Registry.delete(hash)
    RoomMessages.delete_by_room(hash)
  end

  def await_saved(%Identity{} = identity),
    do: Registry.await_saved(identity |> Identity.pub_key() |> Utils.hash())

  def await_saved(msg_data, hash), do: RoomMessages.await_saved(msg_data, hash)
  def on_saved(msg_data, hash, ok_fn), do: RoomMessages.on_saved(msg_data, hash, ok_fn)

  defdelegate add_new_message(message, author, room_pub_key, opts \\ []), to: RoomMessages

  def read_message({_, %Message{}} = msg, %Identity{} = identity),
    do: RoomMessages.read(msg, identity)

  def read_prev_message(
        msg_id,
        %Identity{} = identity,
        predicate
      ) do
    RoomMessages.get_prev_message(msg_id, identity, predicate)
    |> case do
      nil ->
        nil

      message ->
        RoomMessages.read(message, identity)
    end
  end

  def read_next_message(
        msg_id,
        %Identity{} = identity,
        predicate
      ) do
    RoomMessages.get_next_message(msg_id, identity, predicate)
    |> case do
      nil ->
        nil

      message ->
        RoomMessages.read(message, identity)
    end
  end

  def read_message({_, _} = msg_id, %Identity{} = identity, id_map_builder),
    do: RoomMessages.read(msg_id, identity, id_map_builder)

  defdelegate read(
                room,
                room_identity,
                id_map_builder,
                before \\ {nil, 0},
                amount \\ 1000
              ),
              to: RoomMessages

  def update_message(content, msg_id, me, room),
    do: RoomMessages.update_message(content, msg_id, me, room)

  def delete_message(msg_id, room, me),
    do: msg_id |> RoomMessages.delete_message(room, me)

  def add_request(room_hash, user_identity, time) do
    room_hash
    |> get()
    |> Room.add_request(user_identity)
    |> tap(fn %{type: type} = room ->
      if type == :request do
        time
        |> Messages.RoomRequest.new()
        |> add_new_message(user_identity, room.pub_key)
      end
    end)
    |> update()
  end

  def approve_request(room_hash, user_hash, room_identity) do
    if_room_found(room_hash, fn room ->
      room
      |> Room.approve_request(user_hash, room_identity)
      |> update()
    end)
  end

  def approve_requests(room_hash, room_identity) do
    if_room_found(room_hash, fn room ->
      room
      |> Room.approve_requests(room_identity)
      |> update()
    end)
  end

  def join_approved_requests(room_hash, person_identity, time) do
    :todo_refactor_approve_flow

    room_hash
    |> get
    |> Room.join_approved_requests(person_identity)
    |> then(fn {room, joined_identities} ->
      update(room)

      unless [] == joined_identities do
        Log.got_room_key(person_identity, time, room.pub_key)
      end

      joined_identities
    end)
  end

  def is_requested_by?(nil, _), do: false

  def is_requested_by?(room_hash, person_hash) do
    room_hash
    |> get()
    |> Room.is_requested_by?(person_hash)
  end

  def list_pending_requests(room_hash) do
    if_room_found(room_hash, &Room.list_pending_requests/1, [])
  end

  defdelegate update(room), to: Registry

  defp if_room_found(hash, action, default \\ nil) do
    room = get(hash)

    if room do
      room |> action.()
    else
      default
    end
  end
end

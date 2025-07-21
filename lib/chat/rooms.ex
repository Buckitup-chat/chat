defmodule Chat.Rooms do
  @moduledoc "Rooms context"

  alias Chat.Identity
  alias Chat.Rooms.Message
  alias Chat.Rooms.Registry
  alias Chat.Rooms.Room
  alias Chat.Rooms.RoomMessages

  @doc "Returns new room {Identity, Room}"
  def add(me, name, type \\ :public) do
    room_identity = name |> Identity.create()
    room = Room.create(me, room_identity, type)

    room |> Registry.update()

    {room_identity, room}
  end

  @doc "Returns all rooms list"
  def list do
    Registry.all()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.name)
  end

  @doc "Returns rooms {my_rooms, available_rooms}"
  def list(%{} = room_map) do
    Registry.all()
    |> Enum.filter(fn {room_key, room} ->
      room.type in [:public, :request] or Map.has_key?(room_map, room_key)
    end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.name)
    |> Enum.split_with(&Map.has_key?(room_map, &1.pub_key))
  end

  @doc "Returns Room or nil"
  def get(room_key) do
    Registry.find(room_key)
  end

  def delete(room_key) do
    Registry.delete(room_key)
    RoomMessages.delete_by_room(room_key)
  end

  def await_saved(%Identity{} = identity),
    do: Registry.await_saved(identity |> Identity.pub_key())

  def await_saved(msg_data, hash), do: RoomMessages.await_saved(msg_data, hash)
  def on_saved(msg_data, hash, ok_fn), do: RoomMessages.on_saved(msg_data, hash, ok_fn)

  defdelegate add_new_message(message, author, room_pub_key, opts \\ []), to: RoomMessages

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

  def read_message({_, %Message{}} = msg, %Identity{} = identity),
    do: RoomMessages.read(msg, identity)

  def read_message({_, _} = msg_id, %Identity{} = identity),
    do: RoomMessages.read(msg_id, identity)

  defdelegate read(room, room_identity, before \\ {nil, 0}, amount \\ 1000), to: RoomMessages
  defdelegate read_to(room, room_identity, from \\ {nil, 0}, to \\ {0, 0}), to: RoomMessages

  def update_message(content, msg_id, me, room),
    do: RoomMessages.update_message(content, msg_id, me, room)

  def delete_message(msg_id, room, me),
    do: msg_id |> RoomMessages.delete_message(room, me)

  def add_request(room_key, user_identity, _time, _message_added_fn \\ fn _ -> :ok end) do
    room_key
    |> get()
    |> Room.add_request(user_identity)
    |> update()
  end

  def get_request(room, user_public_key), do: Room.get_request(room, user_public_key)

  @doc """
  Approves the room request for user.
  Opts:
    * :public_only - Ignores approval for a non-public room if `true`. Defaults to `false`.
  """
  def approve_request(room_key, user_key, room_identity_or_ciphered, opts \\ []) do
    if_room_found(room_key, fn room ->
      room
      |> Room.approve_request(user_key, room_identity_or_ciphered, opts)
      |> update()
    end)
  end

  def clear_approved_request(room_identity_or_pub_key, person_identity) do
    case room_identity_or_pub_key do
      %Identity{} = identity -> identity |> Identity.pub_key()
      pub_key when is_binary(pub_key) -> pub_key
    end
    |> get()
    |> Room.clear_approved_request(person_identity)
    |> update()
  end

  def requested_by?(room_pub_key, person_public_key) do
    room_pub_key
    |> get()
    |> Room.requested_by?(person_public_key)
  end

  def list_pending_requests(room_key) do
    if_room_found(room_key, &Room.list_pending_requests/1, [])
  end

  def list_approved_requests_for(%Room{} = room, user_public_key) do
    Room.list_approved_requests_for(room, user_public_key)
  end

  def list_approved_requests_for(room_key, user_public_key) do
    room_key
    |> get()
    |> case do
      nil -> []
      room -> list_approved_requests_for(room, user_public_key)
    end
  end

  defdelegate update(room), to: Registry

  defdelegate decipher_identity(encrypted_room_identity, secret), to: Room

  defdelegate decipher_identity_with_key(ciphered_room_identity, person_identity, room_pub_key),
    to: Room

  defp if_room_found(room_or_key, action, default \\ nil)

  defp if_room_found(%Room{} = room, action, _) do
    action.(room)
  end

  defp if_room_found(room_key, action, default) do
    room_key
    |> get
    |> case do
      %Room{} = room -> action.(room)
      _ -> default
    end
  end

  @doc """
  Extracts a room message from a signed parcel.

  ## Returns
  - {index, message} tuple where index is the message index and message is the room message
  """
  @spec extract_message_from_parcel(Chat.SignedParcel.t(), Identity.t() | nil) ::
          {integer(), Message.t()}
  def extract_message_from_parcel(parcel, room_identity \\ nil) do
    # Check if the parcel contains a room message
    if Chat.SignedParcel.message_type(parcel) == :room_message do
      # Extract the message first
      result = Chat.SignedParcel.extract_indexed_message(parcel)

      # If room_identity is provided, validate that the room key matches
      if room_identity do
        room_key = Identity.pub_key(room_identity)

        # Check if any room message entry in the data has the matching room key
        has_matching_room =
          Enum.any?(parcel.data, fn
            {{:room_message, ^room_key, _, _}, _} -> true
            _ -> false
          end)

        if has_matching_room do
          result
        else
          raise ArgumentError, "Parcel does not contain a room message for this room"
        end
      else
        # No room identity check needed
        result
      end
    else
      raise ArgumentError, "Parcel does not contain a room message"
    end
  end
end

defmodule Chat.Rooms.RoomMessageLinks do
  @moduledoc """
  Room links functionality.
  """
  alias Chat.AdminDb
  alias Chat.Identity
  alias Chat.RoomMessageLinksBroker
  alias Chat.Rooms.Room

  def link_hash({_, msg_id}), do: msg_id |> Enigma.hash() |> Base.encode16(case: :lower)

  def get(link_hash), do: link_hash |> RoomMessageLinksBroker.get()

  def create(%Room{type: :public}, %Identity{} = room_identity, {msg_index, msg_id}) do
    secret = msg_id |> Enigma.hash()
    encrypted_room_identity = Room.encrypt_identity(room_identity, secret)
    link_data = {encrypted_room_identity, room_hash(room_identity), msg_index, msg_id}
    link_hash = secret |> Base.encode16(case: :lower)

    AdminDb.put({:room_message_link, link_hash}, link_data)
    RoomMessageLinksBroker.put(link_hash, link_data)
  end

  def create(_, _, _), do: :error

  def sync do
    AdminDb.list({{:room_message_link, 0}, {:"room_link\0", 0}})
    |> Enum.reduce(%{}, fn {{_, hash}, data}, map -> Map.put(map, hash, data) end)
  end

  def is_message_linked?({index, msg_id}) do
    {index, msg_id}
    |> link_hash()
    |> get()
    |> case do
      nil -> false
      _ -> true
    end
  end

  def has_room_linked_messages?(%Identity{} = room_identity) do
    RoomMessageLinksBroker.values()
    |> Enum.any?(fn {_, room_hash, _, _} -> room_hash == room_hash(room_identity) end)
  end

  def cancel_room_links(%Identity{} = room_identity) do
    RoomMessageLinksBroker.values()
    |> Enum.split_with(fn {_, room_hash, _, _} -> room_hash == room_hash(room_identity) end)
    |> then(fn {needed, _} -> needed end)
    |> tap(fn list ->
      Enum.each(list, fn {_, _, _, msg_id} ->
        link_hash = msg_id |> Enigma.hash() |> Base.encode16(case: :lower)
        RoomMessageLinksBroker.forget(link_hash)
      end)
    end)
  end

  defp room_hash(%Identity{} = room_identity), do: room_identity |> Enigma.hash()
end

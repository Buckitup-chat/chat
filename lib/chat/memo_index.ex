defmodule Chat.MemoIndex do
  @moduledoc """
  Index for memos
  """

  alias Chat.Db
  alias Chat.Dialogs
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message
  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.Rooms.Message, as: RoomMessage
  alias Chat.Rooms.Room
  alias Chat.Utils

  def pack(room_or_dialog, storage_key) do
    case {room_or_dialog, storage_key} do
      {_, nil} ->
        []

      {%Dialog{a_key: a_key, b_key: b_key}, memo_key} ->
        [{{:memo_index, a_key, memo_key}, true}, {{:memo_index, b_key, memo_key}, true}]

      {%Room{pub_key: pub_key}, memo_key} ->
        [{{:memo_index, pub_key, memo_key}, true}]
    end
  end

  def add({_, %Message{type: :memo}} = indexed_message, %Dialog{} = dialog, me) do
    key =
      Dialogs.read_message(dialog, indexed_message, me)
      |> Map.fetch!(:content)
      |> Utils.StorageId.from_json_to_key()

    dialog
    |> pack(key)
    |> Enum.each(fn {key, value} -> Db.put(key, value) end)

    indexed_message
  end

  def add(
        {_, %RoomMessage{type: :memo}} = indexed_message,
        %Room{} = room,
        %Identity{} = room_identity
      ) do
    key =
      Rooms.read_message(indexed_message, room_identity)
      |> Map.fetch!(:content)
      |> Utils.StorageId.from_json_to_key()

    room
    |> pack(key)
    |> Enum.each(fn {key, value} -> Db.put(key, value) end)

    indexed_message
  end

  def add(x, _, _), do: x

  def delete(reader_hash, key) do
    Db.delete({:memo_index, reader_hash, key})
  end
end

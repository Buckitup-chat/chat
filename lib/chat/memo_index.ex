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

  def add({_, %Message{type: :memo}} = indexed_message, %Dialog{} = dialog, me) do
    key =
      Dialogs.read_message(dialog, indexed_message, me)
      |> Map.fetch!(:content)
      |> Utils.StorageId.from_json_to_key()

    Db.put({:memo_index, dialog.a_key, key}, true)
    Db.put({:memo_index, dialog.b_key, key}, true)

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

    Db.put({:memo_index, room.pub_key, key}, true)

    indexed_message
  end

  def add(x, _, _), do: x

  def delete(reader_hash, key) do
    Db.delete({:memo_index, reader_hash, key})
  end
end

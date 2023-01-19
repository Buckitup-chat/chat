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

    Db.put({:memo_index, key, dialog.a_key |> Utils.hash()}, true)
    Db.put({:memo_index, key, dialog.b_key |> Utils.hash()}, true)

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

    Db.put({:memo_index, key, room.pub_key |> Utils.hash()}, true)

    indexed_message
  end

  def add(x, _, _), do: x
end

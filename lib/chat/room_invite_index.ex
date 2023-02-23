defmodule Chat.RoomInviteIndex do
  @moduledoc """
  Index room invites
  """
  alias Chat.Db
  alias Chat.Dialogs
  alias Chat.Dialogs.Dialog
  alias Chat.Identity
  alias Chat.Utils.StorageId

  def add({_, _} = indexed_message, %Dialog{} = dialog, %Identity{} = me) do
    key =
      Dialogs.read_message(dialog, indexed_message, me)
      |> Map.fetch!(:content)
      |> StorageId.from_json_to_key()

    Db.put({:room_invite_index, key, dialog.a_key}, true)
    Db.put({:room_invite_index, key, dialog.b_key}, true)

    indexed_message
  end

  def delete(reader_hash, key) do
    Db.delete({:room_invite_index, reader_hash, key})
  end
end

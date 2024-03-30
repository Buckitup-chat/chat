defmodule Chat.RoomInviteIndex do
  @moduledoc """
  Index room invites
  """
  alias Chat.Db
  alias Chat.Dialogs
  alias Chat.Dialogs.Dialog
  alias Chat.Identity
  alias Chat.Utils.StorageId

  def add({_, _} = indexed_message, %Dialog{} = dialog, %Identity{} = me, room_pub_key) do
    key =
      Dialogs.read_message(dialog, indexed_message, me)
      |> Map.fetch!(:content)
      |> StorageId.from_json_to_key()

    room_trace = room_bit_trace(room_pub_key, Chat.Rooms.list() |> Enum.count())

    Db.put({:room_invite_index, dialog.a_key, key}, room_trace)
    Db.put({:room_invite_index, dialog.b_key, key}, room_trace)

    indexed_message
  end

  def delete(reader_hash, key) do
    Db.delete({:room_invite_index, reader_hash, key})
  end

  defp room_bit_trace(room_pub_key, room_count) do
    bit_length =
      trunc(:math.log2(room_count) - 4)
      |> max(1)
      |> min(32)

    <<room_hash_bits::bits-size(bit_length), _::bitstring>> = room_pub_key |> Enigma.hash()
    {bit_length, room_hash_bits}
  end
end

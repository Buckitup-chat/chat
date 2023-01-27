defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.{
    FileIndex,
    Files,
    Memo,
    RoomInvites
  }

  alias Chat.Utils.StorageId

  def delete(%{content: json, type: :room_invite}, _msg_id, _dialog_or_room_hash),
    do: json |> StorageId.from_json() |> RoomInvites.delete()

  def delete(%{content: json, type: :memo}, _msg_id, _dialog_or_room_hash),
    do: json |> StorageId.from_json() |> Memo.delete()

  def delete(%{content: json, type: type}, msg_id, dialog_or_room_hash)
      when type in [:audio, :file, :image, :video] do
    key = StorageId.from_json_to_key(json)
    FileIndex.delete(key, dialog_or_room_hash, msg_id)

    if can_be_deleted?(key, msg_id, dialog_or_room_hash) do
      Files.delete(key)
    end
  end

  def delete(_, _, _), do: :ok

  defp can_be_deleted?(key, msg_id, dialog_or_room_hash) do
    key
    |> FileIndex.list_references(dialog_or_room_hash)
    # References are deleted asynchronously so we can't guarantee current message references is removed.
    |> MapSet.delete(msg_id)
    |> Enum.empty?()
  end
end

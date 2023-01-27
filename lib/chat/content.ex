defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.ChunkedFiles
  alias Chat.MemoIndex
  alias Chat.RoomInviteIndex

  alias Chat.{
    FileIndex,
    Files,
    Memo,
    RoomInvites
  }

  alias Chat.Utils.StorageId

  @spec delete(any(), reader_hash_list :: list(String.t()), msg_id :: any()) :: :ok
  def delete(%{content: json, type: type}, list, msg_id) do
    case type do
      :file -> delete_file(key(json), list, msg_id)
      :image -> delete_file(key(json), list, msg_id)
      :video -> delete_file(key(json), list, msg_id)
      :audio -> delete_file(key(json), list, msg_id)
      :memo -> delete_memo(key(json), list)
      :room_invite -> delete_room_invite(key(json), list)
      _ -> :ok
    end
  end

  defp delete_file(key, reader_hash_list, msg_id) do
    if FileIndex.last_key?(key, reader_hash_list, msg_id) do
      Files.delete(key)
      ChunkedFiles.delete(key)
    end

    reader_hash_list
    |> Enum.each(fn hash ->
      FileIndex.delete(hash, key, msg_id)
    end)
  end

  defp delete_memo(key, reader_hash_list) do
    Memo.delete(key)

    reader_hash_list
    |> Enum.each(fn hash ->
      MemoIndex.delete(hash, key)
    end)
  end

  defp delete_room_invite(key, reader_hash_list) do
    RoomInvites.delete(key)

    reader_hash_list
    |> Enum.each(fn hash ->
      RoomInviteIndex.delete(hash, key)
    end)
  end

  defp key(json), do: StorageId.from_json_to_key(json)
end

defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.ChunkedFiles
  alias Chat.FileIndex
  alias Chat.MemoIndex
  alias Chat.RoomInviteIndex

  alias Chat.{
    Files,
    Memo,
    RoomInvites
  }

  alias Chat.Utils.StorageId

  @spec delete(any(), reader_hash_list :: list(String.t())) :: :ok
  def delete(%{content: json, type: type}, list) do
    case type do
      :file -> delete_file(key(json), list)
      :image -> delete_file(key(json), list)
      :video -> delete_file(key(json), list)
      :memo -> delete_memo(key(json), list)
      :room_invite -> delete_room_invite(key(json), list)
      _ -> :ok
    end
  end

  defp delete_file(key, reader_hash_list) do
    Files.delete(key)
    ChunkedFiles.delete(key)
    # todo: upload delete as well

    reader_hash_list
    |> Enum.each(fn hash ->
      FileIndex.delete(hash, key)
    end)
  end

  defp delete_memo(key, reader_hash_list) do
    Memo.delete(key)

    reader_hash_list
    |> Enum.each(fn hash ->
      MemoIndex.delete(hash, key)
    end)
  end

  defp delete_room_invite(reader_hash_list, key) do
    RoomInvites.delete(key)

    reader_hash_list
    |> Enum.each(fn hash ->
      RoomInviteIndex.delete(hash, key)
    end)
  end

  defp key(json), do: StorageId.from_json_to_key(json)
end

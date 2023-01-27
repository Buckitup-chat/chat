defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

  alias Chat.Db
  alias Chat.Dialogs.Dialog
  alias Chat.Utils

  def get(reader_hash, file_key) do
    reader_hash
    |> db_key(file_key)
    |> Db.get()
  end

  def delete(reader_hash, file_key) do
    reader_hash
    |> db_key(file_key)
    |> Db.delete()
  end

  def save(file_key, reader_hash, message_id, secret) do
    reader_hash
    |> db_key(file_key, message_id)
    |> Db.put(secret)
  end

  def last_key?(file_key, reader_list, message_id) do
    reader_list
    |> Enum.map(fn hash ->
      Db.list({
        key(hash, file_key, 0),
        key(hash, file_key <> "\0", 0)
      })
      |> Stream.map(fn {{:file_index, _reader_hash, _key, msg_id}, _secret} -> msg_id end)
      |> Stream.reject(&(message_id == &1))
      |> Enum.at(0)
    end)
    |> Enum.any?()
    |> Kernel.not()
  end

  defp db_key(reader_hash, file_key, message_id),
    do: {:file_index, reader_hash, file_key, message_id}
end

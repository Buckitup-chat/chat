defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

  alias Chat.Db

  def get(reader_hash, file_key) do
    Db.select(
      {
        db_key(reader_hash, file_key, 0),
        db_key(reader_hash, file_key <> "\0", 0)
      },
      1
    )
    |> Enum.map(&elem(&1, 1))
    |> List.first()
  end

  def delete(reader_hash, file_key, msg_id) do
    reader_hash
    |> db_key(file_key, msg_id)
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
        db_key(hash, file_key, 0),
        db_key(hash, file_key <> "\0", 0)
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

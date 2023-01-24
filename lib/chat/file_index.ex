defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

  alias Chat.Db
  alias Chat.Dialogs.Dialog
  alias Chat.Utils

  def add_file(key, %Dialog{a_key: a, b_key: b}) do
    save(key, a |> Utils.hash())
    save(key, b |> Utils.hash())
  end

  def add_file(key, room_key) do
    save(key, room_key |> Utils.hash())
  end

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

  defp save(file_key, reader_hash) do
    reader_hash
    |> db_key(file_key)
    |> Db.put(true)
  end

  defp db_key(reader_hash, file_key), do: {:file_index, reader_hash, file_key}
end

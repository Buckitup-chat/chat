defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

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
    Chat.Db.get({:file_index, reader_hash, file_key})
  end

  defp save(file_key, reader_hash) do
    Chat.Db.put({:file_index, reader_hash, file_key}, true)
  end
end

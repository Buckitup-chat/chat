defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

  alias Chat.Dialogs.Dialog
  alias Chat.Rooms.Room
  alias Chat.Utils

  def add_file(key, %Dialog{a_key: a, b_key: b}) do
    save(key, a |> Utils.hash())
    save(key, b |> Utils.hash())
  end

  def add_file(key, %Room{pub_key: room_key}) do
    save(key, room_key |> Utils.hash())
  end

  defp save(file_key, reader_hash) do
    Chat.Db.put({:file_index, reader_hash, file_key}, true)
  end
end
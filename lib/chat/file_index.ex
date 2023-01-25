defmodule Chat.FileIndex do
  @moduledoc "Keeps an index of files and keys it"

  alias Chat.Dialogs.Dialog
  alias Chat.Utils

  def add_file(key, %Dialog{a_key: a, b_key: b}, message_id, secret) do
    save(key, a |> Utils.hash(), message_id, secret)
    save(key, b |> Utils.hash(), message_id, secret)
  end

  def add_file(key, room_key, message_id, secret) do
    save(key, room_key |> Utils.hash(), message_id, secret)
  end

  def list_references(key, %Dialog{a_key: a, b_key: b}) do
    MapSet.union(
      list_references(key, Utils.hash(a)),
      list_references(key, Utils.hash(b))
    )
  end

  def list_references(key, reader_hash) do
    Chat.Db.list({
      {:file_index, reader_hash, key, 0},
      {:file_index, reader_hash, "#{key}\0", 0}
    })
    |> Stream.map(fn {{:file_index, _reader_hash, _key, msg_id}, _secret} -> msg_id end)
    |> Enum.into(MapSet.new())
  end

  def get(key, reader_hash) do
    Chat.Db.get_max_one(
      {:file_index, reader_hash, key, 0},
      {:file_index, reader_hash, "#{key}\0", 0}
    )
    |> Enum.at(0, {nil, nil})
    |> elem(1)
  end

  def delete(key, %Dialog{a_key: a, b_key: b}, message_id) do
    delete(key, a |> Utils.hash(), message_id)
    delete(key, b |> Utils.hash(), message_id)
  end

  def delete(key, reader_hash, message_id) do
    Chat.Db.delete({:file_index, reader_hash, key, message_id})
  end

  defp save(key, reader_hash, message_id, secret) do
    Chat.Db.put({:file_index, reader_hash, key, message_id}, secret)
  end
end

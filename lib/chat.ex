defmodule Chat do
  @moduledoc """
  High level functions
  """

  alias Chat.Db.Copying

  def db_get(key) do
    case key do
      {:file_chunk, file_key, first, last} -> read_chunk({first, last}, file_key)
      {:file_chunk, file_key, first} -> read_chunk(first, file_key)
      _ -> Chat.Db.get(key)
    end
  end

  def db_put(key, value) do
    Chat.Db.put(key, value)
    Copying.await_written_into([key], Chat.Db.db())
  end

  def db_has?(key) do
    case key do
      {:file_chunk, key, first, last} -> Chat.FileFs.has_file?({key, first, last})
      key -> Chat.Db.has_key?(key)
    end
  end

  defp read_chunk(range, key) when is_tuple(range) do
    {data, _last} =
      Chat.FileFs.read_exact_file_chunk(range, key, path())

    data
  end

  defp read_chunk(first, key) do
    Chat.FileFs.read_file_chunk(first, key, path())
  end

  defp path, do: CubDB.data_dir(Chat.Db.db()) <> "_files"
end

defmodule Chat do
  @moduledoc """
  High level functions
  """

  def db_get(key) do
    case key do
      {:file_chunk, file_key, first, last} -> read_chunk({first, last}, file_key)
      _ -> Chat.Db.get(key)
    end
  end

  def db_put(key, value) do
    case key do
      {:file_chunk, file_key, first, last} -> write_chunk(value, {file_key, first, last})
      _ -> Chat.Db.put(key, value)
    end
  end

  defp read_chunk(range, key) do
    {data, _last} =
      Chat.FileFs.read_exact_file_chunk(range, key, path())

    data
  end

  defp write_chunk(value, chunk_params) do
    Chat.FileFs.write_file(value, chunk_params, path())
  end

  defp path, do: CubDB.data_dir(Chat.Db.db()) <> "_files"
end

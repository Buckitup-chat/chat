defmodule Chat do
  @moduledoc """

  """

  def db_get(key) do
    case key do
      {:file_chunk, file_key, first, last} -> read_chunk({first, last}, file_key)
      _ -> Chat.Db.get(key)
    end
  end

  defp read_chunk(range, key) do
    path = CubDB.data_dir(Chat.Db.db()) <> "_files"

    {data, _last} =
      Chat.FileFs.read_exact_file_chunk(range, key, path)

    data
  end
end

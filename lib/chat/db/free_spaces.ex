defmodule Chat.Db.FreeSpaces do
  @moduledoc "Free space in MB of databases"

  alias Chat.Db.{InternalDb, MainDb, BackupDb, CargoDb}
  alias Chat.Db.Maintenance

  def get_all() do
    spaces =
      [InternalDb, MainDb, BackupDb, CargoDb]
      |> Stream.map(&{&1 |> atomize_db_name(), &1 |> get_one()})
      |> Enum.into(%{})

    media_db_space = media_db_space(spaces)

    spaces
    |> Map.put(:media_db, media_db_space)
    |> Enum.map(fn {key, value} ->
      value =
        case value do
          -1 -> "Not found"
          value -> value |> bytes_to_MB()
        end

      {key, value}
    end)
    |> Enum.into(%{})
  end

  defp get_one(db) do
    pid = Process.whereis(db)

    case pid do
      nil -> -1
      _pid -> db |> Maintenance.db_free_space()
    end
  end

  defp bytes_to_MB(space) do
    space
    |> Kernel./(1024 * 1024)
    |> round()
    |> Integer.to_string()
    |> Kernel.<>(" MB")
  end

  defp atomize_db_name(InternalDb), do: :internal_db
  defp atomize_db_name(MainDb), do: :main_db
  defp atomize_db_name(BackupDb), do: :backup_db
  defp atomize_db_name(CargoDb), do: :cargo_db

  defp media_db_space(spaces) do
    media_dbs = [:backup_db, :cargo_db]

    media_db_space =
      media_dbs
      |> Enum.map(&Map.get(spaces, &1))
      |> Enum.sum()

    cond do
      media_db_space >= -1 -> media_db_space + 1
      true -> -1
    end
  end
end

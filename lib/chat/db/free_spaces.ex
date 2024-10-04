defmodule Chat.Db.FreeSpaces do
  @moduledoc "Free space in MB of databases"

  alias Chat.Db.{BackupDb, CargoDb, InternalDb, MainDb, OnlinersDb}
  alias Chat.Db.Maintenance

  def get_all do
    spaces =
      [InternalDb, MainDb, BackupDb, CargoDb, OnlinersDb]
      |> Stream.map(&{&1 |> atomize_db_name(), &1 |> get_one()})
      |> Enum.into(%{})

    media_dbs = [:backup_db, :cargo_db, :onliners_db]

    media_db_space =
      media_dbs
      |> Enum.map(&Map.get(spaces, &1))
      |> Enum.max()

    spaces
    |> Map.put(:media_db, media_db_space)
    |> Map.drop(media_dbs)
    |> Enum.map(fn {key, value} ->
      value =
        case value do
          -1 -> "Not found"
          value -> value |> bytes_to_mega_bytes()
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

  defp bytes_to_mega_bytes(space) do
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
  defp atomize_db_name(OnlinersDb), do: :onliners_db
end

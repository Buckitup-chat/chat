defmodule Chat.Db.Maintenance do
  @moduledoc "DB size and operation mode functions"

  @free_space_buffer_100mb 100 * 1024 * 1024

  def path_writable_size(path) do
    path_free_space(path) - @free_space_buffer_100mb
  end

  def path_free_space(path) do
    System.cmd("df", ["-Pk", path])
    |> elem(0)
    |> String.split("\n", trim: true)
    |> List.last()
    |> String.split(" ", trim: true)
    |> Enum.at(3)
    |> String.to_integer()
    |> Kernel.*(1024)
  rescue
    _ -> 0
  end

  def path_to_device(path) do
    with {data, 0} <- System.cmd("df", ["-P", path]),
         [_header, row] <- String.split(data, "\n", trim: true),
         [full_device | _] <- String.split(row, " ", trim: true) do
      full_device
    else
      _ -> nil
    end
  end

  def device_to_path(device) do
    with {data, 0} <- System.cmd("df", ["-P"]),
         [_header | rows] <- String.split(data, "\n", trim: true),
         row <- Enum.find(rows, &String.starts_with?(&1, device)),
         [_, _, _, _, _, path] <- String.split(row, " ", trim: true) do
      path
    else
      _ -> nil
    end
  end

  def db_size(db) do
    db
    |> CubDB.current_db_file()
    |> File.stat!()
    |> Map.get(:size)
  end

  def db_free_space(db) do
    db
    |> CubDB.data_dir()
    |> path_free_space()
  end
end

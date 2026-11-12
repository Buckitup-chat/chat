defmodule Chat.Data.File.ChunkStore do
  @moduledoc """
  Filesystem storage for raw encrypted chunk bytes of one storage unit.

  Every function takes the `%Unit{}` first; blobs live under
  `Unit.path(unit, :pq_files)` as `<shard>/f_<hex>/<index>`.
  """

  alias Chat.Storage.Unit

  @index_padding 10

  def put(%Unit{} = unit, file_id, chunk_index, binary) do
    path = chunk_path(unit, file_id, chunk_index)
    dir = Path.dirname(path)
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(tmp, binary) do
      File.rename(tmp, path)
    end
  end

  def fetch(%Unit{} = unit, file_id, chunk_index) do
    unit |> chunk_path(file_id, chunk_index) |> File.read()
  end

  def count_on_disk(%Unit{} = unit, file_id) do
    unit
    |> file_dir(file_id)
    |> File.ls()
    |> case do
      {:ok, entries} -> entries |> Enum.reject(&String.ends_with?(&1, ".tmp")) |> length()
      {:error, _reason} -> 0
    end
  end

  def delete_file(%Unit{} = unit, file_id) do
    unit |> file_dir(file_id) |> File.rm_rf()
    :ok
  end

  def sweep_tmp_files(%Unit{} = unit, max_age_ms) do
    cutoff = System.os_time(:millisecond) - max_age_ms

    unit
    |> Unit.path(:pq_files)
    |> Path.join("**/*.tmp")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %{mtime: mtime}} when mtime * 1000 < cutoff -> File.rm(path)
        _ -> :ok
      end
    end)
  end

  def available_space(%Unit{} = unit) do
    path = existing_ancestor(Unit.path(unit, :pq_files))

    case System.cmd("df", ["-B1", "--output=avail", path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> List.last()
        |> String.trim()
        |> Integer.parse()
        |> case do
          {bytes, _} -> {:ok, bytes}
          :error -> {:error, :parse_error}
        end

      _ ->
        {:error, :df_failed}
    end
  end

  def sync_dir(%Unit{} = unit, file_id) do
    dir = file_dir(unit, file_id)

    case :file.open(String.to_charlist(dir), [:read]) do
      {:ok, fd} ->
        :file.datasync(fd)
        :file.close(fd)

      _ ->
        :ok
    end
  end

  def file_dir(%Unit{} = unit, "f_" <> hex = file_id) do
    shard = String.slice(hex, -2, 2)

    Path.join([Unit.path(unit, :pq_files), shard, file_id])
  end

  defp chunk_path(unit, file_id, chunk_index) do
    pad_index = chunk_index |> to_string() |> String.pad_leading(@index_padding, "0")

    Path.join(file_dir(unit, file_id), pad_index)
  end

  # `pq_files` is created on the first write; `df` needs a path that exists
  defp existing_ancestor(path) do
    cond do
      File.exists?(path) -> path
      Path.dirname(path) == path -> path
      true -> path |> Path.dirname() |> existing_ancestor()
    end
  end
end

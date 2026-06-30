defmodule Chat.Data.File.ChunkStore do
  @moduledoc "Filesystem storage for raw encrypted chunk bytes."

  alias Chat.Db.Common

  @index_padding 10

  def put(file_id, chunk_index, binary, base_dir \\ nil) do
    path = chunk_path(file_id, chunk_index, base_dir)
    dir = Path.dirname(path)
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(tmp, binary, [:raw, :sync]) do
      File.rename(tmp, path)
    end
  end

  def fetch(file_id, chunk_index, base_dir \\ nil) do
    file_id |> chunk_path(chunk_index, base_dir) |> File.read()
  end

  def delete_file(file_id) do
    file_id |> file_dir(nil) |> File.rm_rf()
    :ok
  end

  def sweep_tmp_files(max_age_ms, base_dir \\ nil) do
    cutoff = System.os_time(:millisecond) - max_age_ms

    pq_dir(base_dir)
    |> Path.join("**/*.tmp")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %{mtime: mtime}} when mtime * 1000 < cutoff -> File.rm(path)
        _ -> :ok
      end
    end)
  end

  def available_space do
    path = pq_dir(nil)

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

  defp chunk_path(file_id, chunk_index, override_base_dir) do
    pad_index = chunk_index |> to_string() |> String.pad_leading(@index_padding, "0")

    Path.join(file_dir(file_id, override_base_dir), pad_index)
  end

  defp file_dir(file_id, override_base_dir) do
    "f_" <> hex = file_id
    shard = String.slice(hex, -2, 2)

    Path.join([pq_dir(override_base_dir), shard, file_id])
  end

  defp pq_dir(base_dir) do
    case base_dir do
      nil -> Path.join(Common.get_chat_db_env(:files_base_dir), "pq_files")
      dir -> Path.join(dir, "pq_files")
    end
  end
end

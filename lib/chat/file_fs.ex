defmodule Chat.FileFs do
  @moduledoc "Helpers for file storage"

  alias Chat.Db.Common

  @int_padding 20

  def write_file(data, {_, _, _} = keys, prefix \\ nil) do
    keys
    |> file_path(build_path(prefix))
    |> tap(&create_dirs/1)
    |> File.open([:write, :sync], fn file ->
      :ok = IO.binwrite(file, data)
      :file.datasync(file)
    end)
  end

  @spec read_file_chunk(offset :: non_neg_integer(), key :: String.t()) ::
          {binary(), non_neg_integer()}
  def read_file_chunk(first, key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> list_files()
    |> Enum.find(fn filename ->
      start =
        filename
        |> Path.split()
        |> Enum.take(-2)
        |> List.first()
        |> String.to_integer()

      start == first
    end)
    |> then(fn filename ->
      data = File.open!(filename, [:binary, :read], &IO.binread(&1, :eof))

      last =
        filename
        |> Path.split()
        |> List.last()
        |> String.to_integer()

      {data, last}
    end)
  end

  def stream_file_chunks(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> list_files()
    |> Enum.sort()
    |> Stream.map(fn file ->
      File.open!(file, [:binary, :read], &IO.binread(&1, :eof))
    end)
  end

  def delete_file(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> File.rm_rf!()
  end

  def count_size_stored(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> list_files()
    |> Enum.map(fn filename ->
      filename
      |> Path.split()
      |> Enum.take(-2)
      |> Enum.map(&String.to_integer/1)
      |> then(fn [first, last] -> max(last - first + 1, 0) end)
    end)
    |> Enum.sum()
  end

  def file_size(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> list_files()
    |> Enum.sort(:desc)
    |> List.first()
    |> Path.split()
    |> List.last()
    |> String.to_integer()
    |> Kernel.+(1)
  rescue
    _ -> 0
  end

  ##
  ##   Implementations
  ##

  defp populate_level(path) do
    path
    |> File.ls!()
    |> Enum.map(&Path.join([path, &1]))
  end

  defp list_files(path) do
    path
    |> populate_level()
    |> Enum.map(&populate_level/1)
    |> List.flatten()
  end

  defp build_path(nil), do: Common.get_chat_db_env(:files_base_dir)
  defp build_path(str), do: str

  defp file_path({binary_key, first, last}, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    [dir, file] =
      [first, last]
      |> Enum.map(fn int ->
        int
        |> to_string()
        |> String.pad_leading(@int_padding, "0")
      end)

    [prefix, hc(key), key, dir, file] |> Path.join()
  end

  defp key_path(binary_key, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    [prefix, hc(key), key] |> Path.join()
  end

  defp hc(str), do: String.slice(str, 0, 2)

  defp create_dirs(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()
  end
end

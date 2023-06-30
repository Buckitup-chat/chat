defmodule Chat.FileFs.Dir3 do
  @moduledoc """
  Filesystem files storing

  Uses following directory structure: prefix/file_key/start_offset/end_offset
  """

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

  def has_file?({_, _, _} = keys, prefix \\ nil) do
    keys
    |> file_path(build_path(prefix))
    |> File.exists?()
  end

  def read_exact_file_chunk({first, last}, key, prefix \\ nil) do
    {key, first, last}
    |> file_path(build_path(prefix))
    |> File.open([:binary, :read], &IO.binread(&1, :all))
  end

  def read_file_chunk(first, key, prefix \\ nil) do
    file_dir_path = key_path(key, build_path(prefix))
    first_offset_name = offset_name(first)

    Path.join(file_dir_path, first_offset_name)
    |> File.ls!()
    |> case do
      [] ->
        {{:error, :empty_dir}, :error}

      [last_offset_name | _] ->
        last = last_offset_name |> String.to_integer()

        [file_dir_path, first_offset_name, last_offset_name]
        |> Path.join()
        |> File.open([:binary, :read], &IO.binread(&1, :all))
        |> then(&{&1, last})
    end
  rescue
    _ -> {{:error, :no_file}, :error}
  end

  def stream_file_chunks(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> list_files()
    |> Enum.sort()
    |> Stream.map(fn file ->
      File.open!(file, [:binary, :read], &IO.binread(&1, :all))
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

  def relative_filenames(prefix) do
    dir = build_path(prefix)

    if File.dir?(dir) do
      dir
      |> list_files()
      |> Enum.flat_map(&populate_level/1)
      |> Enum.flat_map(&populate_level/1)
      |> Enum.map(&String.slice(&1, (String.length(dir) + 1)..-1))
    else
      []
    end
  end

  ##
  ##   Implementations
  ##

  defp populate_level(path) do
    path
    |> File.ls!()
    |> Enum.map(&Path.join([path, &1]))
  rescue
    _ -> []
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
      |> Enum.map(&offset_name/1)

    [prefix, hc(key), key, dir, file] |> Path.join()
  end

  defp key_path(binary_key, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    [prefix, hc(key), key] |> Path.join()
  end

  defp offset_name(int) do
    int
    |> to_string()
    |> String.pad_leading(@int_padding, "0")
  end

  defp hc(str), do: String.slice(str, 0, 2)

  defp create_dirs(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()
  end
end

defmodule Chat.FileFs.Dir2 do
  @moduledoc """
  Filesystem files storing

  Uses following directory structure: prefix/file_key/start_offset-end_offset
  """
  import Chat.FileFs.Common

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
    first_offset_name = offset_name(first) <> "-"

    File.ls!(file_dir_path)
    |> Enum.find(fn filename ->
      String.starts_with?(filename, first_offset_name)
    end)
    |> case do
      nil ->
        {{:error, :file_not_found}, :error}

      filename ->
        last =
          filename
          |> String.slice(-@int_padding, @int_padding)
          |> String.to_integer()

        Path.join(file_dir_path, filename)
        |> File.open([:binary, :read], &IO.binread(&1, :all))
        |> then(&{&1, last})
    end
  rescue
    _ -> {{:error, :no_dir}, :error}
  end

  defp file_path({binary_key, first, last}, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    file =
      [first, last]
      |> Enum.map_join("-", &offset_name/1)

    [prefix, hc(key), key, file] |> Path.join()
  end

  defp create_dirs(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()
  end
end

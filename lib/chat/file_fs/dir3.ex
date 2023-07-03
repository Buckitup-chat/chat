defmodule Chat.FileFs.Dir3 do
  @moduledoc """
  Filesystem files storing

  Uses following directory structure: prefix/file_key/start_offset/end_offset
  """

  import Chat.FileFs.Common

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

  ##
  ##   Implementations
  ##

  defp file_path({binary_key, first, last}, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    [dir, file] =
      [first, last]
      |> Enum.map(&offset_name/1)

    [prefix, hc(key), key, dir, file] |> Path.join()
  end
end

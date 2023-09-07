defmodule Chat.FileFs do
  @moduledoc "Helpers for file storage"

  import Chat.FileFs.Common

  require Logger

  alias Chat.FileFs.Dir2
  alias Chat.FileFs.Dir3

  @int_padding 20
  @dir2_chunkname_length @int_padding + 1 + @int_padding

  def write_file(data, {_, _, _} = keys, prefix \\ nil) do
    Dir2.write_file(data, keys, prefix)
  end

  def has_file?({_, first, last} = keys, prefix \\ nil) do
    case file_stats(keys, prefix) do
      {:ok, stat} -> first + stat.size == last + 1
      _ -> false
    end
  end

  def file_stats({_, _, _} = keys, prefix \\ nil) do
    dir_path = build_path(prefix)

    keys
    |> Dir2.file_path(dir_path)
    |> File.stat(time: :posix)
    |> case do
      {:ok, _} = good -> good
      _ -> keys |> Dir3.file_path(dir_path) |> File.stat(time: :posix)
    end
  end

  def read_exact_file_chunk({_first, last} = offsets, key, prefix) do
    case Dir2.read_exact_file_chunk(offsets, key, prefix) do
      {:ok, data} ->
        {data, last}

      _ ->
        {:ok, data} = Dir3.read_exact_file_chunk(offsets, key, prefix)
        {data, last}
    end
  end

  @spec read_file_chunk(offset :: non_neg_integer(), key :: String.t()) ::
          {binary(), non_neg_integer()}
  def read_file_chunk(first, key, prefix \\ nil) do
    case Dir2.read_file_chunk(first, key, prefix) do
      {{:ok, data}, last} ->
        {data, last}

      _ ->
        {{:ok, data}, last} = Dir3.read_file_chunk(first, key, prefix)
        {data, last}
    end
  end

  def stream_file_chunks(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> chunks_in_file_dir()
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
    |> chunks_in_file_dir()
    |> Stream.map(fn chunk_path ->
      chunk_path
      |> String.slice(-@dir2_chunkname_length, @dir2_chunkname_length)
      |> String.split(["-", "/", "\\"])
      |> Enum.map(&String.to_integer/1)
      |> then(fn [first, last] -> max(last - first + 1, 0) end)
    end)
    |> Enum.sum()
  end

  def file_size(key, prefix \\ nil) do
    key_path(key, build_path(prefix))
    |> chunks_in_file_dir()
    |> Enum.max()
    |> String.slice(-@int_padding, @int_padding)
    |> String.to_integer()
    |> Kernel.+(1)
  rescue
    _ -> 0
  end

  def list_all_db_keys(prefix) do
    dir = build_path(prefix)
    dir_length = String.length(dir)

    if File.dir?(dir) do
      dir
      |> list_files()
      |> Stream.flat_map(&chunks_in_file_dir/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&String.slice(&1, (dir_length + 1)..-1))
      |> Stream.map(&filename_to_db_key/1)
      |> Enum.to_list()
      |> tap(&check_integrity(&1, prefix))
    else
      []
    end
  end

  def list_file_errors(prefix) do
    dir = build_path(prefix)
    dir_length = String.length(dir)

    if File.dir?(dir) do
      dir
      |> list_files()
      |> Stream.flat_map(&chunks_in_file_dir/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&String.slice(&1, (dir_length + 1)..-1))
      |> Stream.map(&filename_to_db_key/1)
      |> Enum.to_list()
      |> check_integrity(prefix)
    else
      []
    end
  end

  ##
  ##   Implementations
  ##
  defp filename_to_db_key(<<
         _::binary-size(3),
         hash::binary-size(64),
         ?/,
         start::binary-size(20),
         _::binary-size(1),
         finish::binary-size(20)
       >>) do
    {
      :file_chunk,
      hash |> Base.decode16!(case: :lower),
      start |> String.to_integer(),
      finish |> String.to_integer()
    }
  end

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

  defp chunks_in_file_dir(path) do
    File.ls!(path)
    |> Enum.map(fn dir_or_fn ->
      case String.length(dir_or_fn) do
        @int_padding ->
          [path, dir_or_fn]
          |> Path.join()
          |> populate_level()
          |> List.first()

        @dir2_chunkname_length ->
          [path, dir_or_fn]
          |> Path.join()
      end
    end)
  rescue
    _ -> []
  end

  defp check_integrity(key_list, prefix) do
    total = Enum.count(key_list)

    broken =
      key_list
      |> Enum.map(fn {_, file_key, first, last} ->
        key = {file_key, first, last}
        meta_size = last - first + 1
        result = file_stats(key, prefix)

        cond do
          result |> not_found?() ->
            {:no_file, file_key |> Base.encode16(case: :lower), file_key, first, last}

          result |> correct_size?(meta_size) ->
            :ok

          true ->
            [
              file_size: result |> elem(1) |> Map.get(:size),
              meta_size: last - first + 1,
              meta: {file_key |> Base.encode16(case: :lower), key}
            ]
        end
      end)
      |> Enum.reject(&match?(:ok, &1))

    broken_count = Enum.count(broken)

    if broken_count > 0 do
      log_broken(Enum.take(broken, 10), broken_count, total, prefix)
    end

    broken
  end

  defp not_found?(stat_result), do: not match?({:ok, _}, stat_result)
  defp correct_size?({:ok, %{size: size}}, correct), do: size == correct

  defp log_broken(list, broken, total, prefix) do
    [
      "[chat] ",
      "[file_fs] ",
      "Integrity broken on #{prefix}",
      "\nBroken #{broken} of #{total}, like: \n#{inspect(list, pretty: true)}"
    ]
    |> Logger.warning()
  end
end

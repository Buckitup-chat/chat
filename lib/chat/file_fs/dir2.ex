defmodule Chat.FileFs.Dir2 do
  @moduledoc """
  Filesystem files storing

  Uses following directory structure: prefix/file_key/start_offset-end_offset
  """
  import Chat.FileFs.Common

  require Logger

  @int_padding 20

  def write_file(data, {_, first, last} = keys, prefix \\ nil) do
    data_size = byte_size(data)
    meta_size = last - first + 1

    if data_size != meta_size do
      log_ingress_chunk_integrity_error(keys, actual: data_size, declared: meta_size)
    end

    path = file_path(keys, build_path(prefix))
    create_dirs(path)

    File.open(path, [:write, :sync], fn file ->
      :ok = IO.binwrite(file, data)
      :ok = :file.datasync(file)
    end)
    |> tap(fn _ ->
      case File.stat(path, time: :posix) do
        {:ok, stat} ->
          if stat.size != data_size do
            log_written_chunk_integrity_error(
              keys,
              {data_size, meta_size},
              {:wrong_size, stat.size}
            )
          end

        _ ->
          log_written_chunk_integrity_error(keys, {data_size, meta_size}, {:no_file, path})
      end
    end)
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

  def file_path({binary_key, first, last}, prefix) do
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

  defp log_ingress_chunk_integrity_error(keys, opts) do
    [
      inspect(keys),
      "\n    data size: ",
      inspect(opts[:actual]),
      "\n    declared size: ",
      inspect(opts[:declared])
    ]
    |> log()
  end

  defp log_written_chunk_integrity_error(keys, {data, meta}, error) do
    case error do
      {:wrong_size, file_size} -> "Wrong size written: #{file_size} "
      {:no_file, path} -> "File is not written #{path} "
    end
    |> then(
      &[
        &1,
        "data: ",
        inspect(data),
        "meta: ",
        inspect(meta),
        "\n",
        inspect(keys)
      ]
    )
    |> log()
  end

  defp log(msg) do
    ["[chat] ", "[file_fs] " | msg]
    |> Logger.warning()
  end
end

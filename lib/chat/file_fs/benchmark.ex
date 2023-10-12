defmodule Chat.FileFs.Benchmark do
  @moduledoc "Benchmark performance"
  # coveralls-ignore-start
  @chunk_size 10 * 1024 * 1024

  alias Chat.FileFs

  def small(path) do
    {write_time, keys} = fn -> generate(path, count: 200, size: 200_000) end |> measure()
    {read_time, _} = fn -> read(path, keys) end |> measure()
    {delete_time, _} = fn -> remove(path, keys) end |> measure()

    {write_time, read_time, delete_time} |> s()
  end

  def medium(path) do
    {write_time, keys} = fn -> generate(path, count: 50, size: 5_000_000) end |> measure()
    {read_time, _} = fn -> read(path, keys) end |> measure()
    {delete_time, _} = fn -> remove(path, keys) end |> measure()

    {write_time, read_time, delete_time} |> s()
  end

  def large(path) do
    {write_time, keys} = fn -> generate(path, count: 7, size: 70_000_000) end |> measure()
    {read_time, _} = fn -> read(path, keys) end |> measure()
    {delete_time, _} = fn -> remove(path, keys) end |> measure()

    {write_time, read_time, delete_time} |> s()
  end

  def all(path) do
    {write_sm, keys_sm} = fn -> generate(path, count: 200, size: 200_000) end |> measure()
    {write_md, keys_md} = fn -> generate(path, count: 50, size: 5_000_000) end |> measure()
    {write_lg, keys_lg} = fn -> generate(path, count: 7, size: 70_000_000) end |> measure()

    keys =
      [keys_sm, keys_md, keys_lg]
      |> List.flatten()

    {read_time, _} = fn -> read(path, keys) end |> measure()
    {delete_time, _} = fn -> remove(path, keys) end |> measure()

    {write_sm + write_md + write_lg, read_time, delete_time} |> s()
  end

  defp generate(path, count: n, size: size) do
    for i <- 1..n,
        first <- 0..size//@chunk_size,
        last = min(first + @chunk_size - 1, size - 1),
        file_key = "#{i}_test_file" |> Enigma.hash(),
        content = :crypto.strong_rand_bytes(last - first + 1) do
      content
      |> FileFs.write_file({file_key, first, last}, path)

      file_key
    end
  end

  defp read(path, keys) do
    keys
    |> Stream.map(&FileFs.stream_file_chunks(&1, path))
    |> Stream.map(&Enum.join/1)
    |> Stream.map(&byte_size/1)
    |> Enum.sum()
  end

  defp remove(path, keys) do
    keys
    |> Enum.each(&FileFs.delete_file(&1, path))
  end

  defp measure(action) do
    :timer.tc(action)
  end

  defp s({a, b, c}), do: {a / 1_000_000, b / 1_000_000, c / 1_000_000}
  # coveralls-ignore-end
end

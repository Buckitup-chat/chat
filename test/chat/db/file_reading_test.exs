defmodule Chat.Db.WriteQueue.FileReaderTest do
  @moduledoc """
  Test file reading in case whe have two streams of reading from filesystem

  Stream keys should not intersect
  In best case scenario they should optimise, like reading for one stream should yield in both streams
  """
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Db.WriteQueue.FileReader

  defmodule FileFsMock do
    def read_exact_file_chunk({first, last}, _, _) do
      Process.sleep(:rand.uniform(450) + 50)
      size = last - first + 1

      {
        " " |> String.duplicate(size),
        size
      }
    end
  end

  rewire(FileReader, [{Chat.FileFs, FileFsMock}])

  test "file reading should not mess up streams" do
    start_file_reader()
    |> run_streams()
    |> assert_streams_read_completely()
  end

  defp start_file_reader do
    name = WriteQueue.FileReader.ConcurrentReadTest
    supervisor = WriteQueue.FileReader.ConcurrentReadTestSupervisor

    {:ok, _} = Task.Supervisor.start_link(name: supervisor)
    {:ok, _pid} = FileReader.start_link(name: name, read_supervisor: supervisor)

    name
  end

  defp run_streams(name) do
    generate_n_keys_for_m_streams(500, 2)
    |> process_read_streams(name)
  end

  defp generate_n_keys_for_m_streams(n, m) do
    for i <- 1..(n * m) do
      {:file_chunk, i, 0, i}
    end
    |> Enum.chunk_every(n)
    |> then(&%{keys: &1})
  end

  defp process_read_streams(context, name) do
    context.keys
    |> Task.async_stream(fn keys ->
      readers = add_tasks(keys, name)
      read_keys = MapSet.new()

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      Process.sleep(100)
      {files_read, readers} = yield_files(readers, name)
      read_keys = MapSet.union(read_keys, files_read)

      {read_keys, readers}
    end)
    |> Enum.map(fn {:ok, x} -> x end)
    |> then(&Map.put(context, :read_keys, &1))
  end

  defp add_tasks(keys, name) do
    keys
    |> Enum.map(&FileReader.add_task(name, &1, __DIR__))
  end

  defp yield_files(readers, name) do
    {file, rest} = FileReader.yield_file(name, readers)

    {more_files, still_tasks} =
      Enum.split_with(rest, fn x -> match?({{:file_chunk, _, _, _}, _}, x) end)

    [file | more_files]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {key, _content} -> key end)
    |> MapSet.new()
    |> then(&{&1, still_tasks})
  end

  defp assert_streams_read_completely(context) do
    context.keys
    |> Enum.zip(context.read_keys)
    |> Enum.map(fn {initial, {read, unread}} ->
      assert Enum.count(initial) == MapSet.size(read)
      assert unread == []
    end)
  end
end

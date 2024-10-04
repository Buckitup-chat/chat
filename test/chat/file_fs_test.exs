defmodule Chat.FileFsTest do
  use ExUnit.Case

  import Chat.FileFs.Common, only: [binread: 1]

  describe "old FS operations" do
    setup do
      path =
        System.tmp_dir!()
        |> Path.join("old_fs_test")
        |> tap(&File.mkdir_p!/1)

      file_key = "old_fs_test" |> Enigma.hash()
      content = :crypto.strong_rand_bytes(:rand.uniform(1_000_000))

      full_path =
        [
          path,
          file_key |> Base.encode16(case: :lower) |> String.slice(0, 2),
          file_key |> Base.encode16(case: :lower),
          0 |> to_string() |> String.pad_leading(20, "0")
        ]
        |> Path.join()
        |> tap(&File.mkdir_p!/1)

      (byte_size(content) - 1)
      |> to_string()
      |> String.pad_leading(20, "0")
      |> then(&Path.join(full_path, &1))
      |> File.write!(content)

      on_exit(fn ->
        File.rm_rf!(path)
      end)

      %{
        path: path,
        db_key: {:file_chunk, file_key, 0, byte_size(content) - 1},
        content: content
      }
    end

    test "read chunk", %{path: path, db_key: {_, key, first, last}, content: content} do
      assert {^content, ^last} = Chat.FileFs.read_file_chunk(first, key, path)
    end

    test "read exact chunk", %{path: path, db_key: {_, key, first, last}, content: content} do
      assert {^content, ^last} = Chat.FileFs.read_exact_file_chunk({first, last}, key, path)
    end

    test "stream file", %{path: path, db_key: {_, key, _, _}, content: content} do
      assert ^content =
               Chat.FileFs.stream_file_chunks(key, path) |> Enum.to_list() |> List.first()
    end
  end

  describe "file operations" do
    test "binread" do
      dir = make_temp_dir("binread")
      file1 = make_file(dir, 4096)
      file2 = make_file(dir, 4095)
      file3 = make_file(dir, 4097)
      file4 = make_file(dir, 0)

      assert 4095 = file2 |> read_file() |> byte_size()
      assert 4096 = file1 |> read_file() |> byte_size()
      assert 4097 = file3 |> read_file() |> byte_size()
      assert 0 = file4 |> read_file() |> byte_size()

      clear_temp_dir(dir)
    end

    defp read_file(filename) do
      filename
      |> File.open([:binary, :read], &binread/1)
      |> case do
        {:ok, data} -> data
        other -> {:error, other}
      end
    end

    defp make_file(dir, length) do
      dir
      |> Path.join(UUID.uuid4())
      |> tap(fn filename ->
        data = :crypto.strong_rand_bytes(length)

        File.open(filename, [:write, :sync], fn file ->
          :ok = IO.binwrite(file, data)
        end)
      end)
    end

    defp make_temp_dir(suffix) do
      System.tmp_dir!()
      |> Path.join(suffix)
      |> tap(&File.mkdir_p!/1)
    end

    defp clear_temp_dir(dir) do
      File.rm_rf(dir)
    end
  end
end

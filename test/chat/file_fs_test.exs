defmodule Chat.FileFsTest do
  use ExUnit.Case

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
end

defmodule Chat.ChunkedFilesTest do
  use ExUnit.Case, async: false

  alias Chat.ChunkedFiles
  alias Chat.FileFs

  test "should generate a key and a secret on upload start, save chunks by key and able to read full file decrypting with secret" do
    key = UUID.uuid4() |> Enigma.hash()
    secret = ChunkedFiles.new_upload(key)

    assert 32 = byte_size(secret)

    first = "some part of info "
    second = "another part"
    size = String.length(first) + String.length(second)

    ChunkedFiles.save_upload_chunk(key, {0, 17}, 30, first)
    assert false == ChunkedFiles.complete_upload?(key, size)

    ChunkedFiles.save_upload_chunk(key, {18, 29}, 30, second)
    assert ChunkedFiles.complete_upload?(key, size)

    recovered = ChunkedFiles.read({key, secret})

    assert recovered == Enum.join([first, second])

    assert ^size = FileFs.file_size(key)
  end

  test "should forget key" do
    key = UUID.uuid4() |> Enigma.hash()
    _secret = ChunkedFiles.new_upload(key)
    assert nil != Chat.ChunkedFilesBroker.get(key)

    ChunkedFiles.mark_consumed(key)
    assert nil == Chat.ChunkedFilesBroker.get(key)
  end

  test "ranges should split correct" do
    size = 23.5461 |> mb()

    correct = [{0, mb(10) - 1}, {mb(10), mb(20) - 1}, {mb(20), 24_689_874}]

    assert correct == ChunkedFiles.file_chunk_ranges(size)
  end

  defp mb(n) when is_integer(n), do: n * 1024 * 1024
  defp mb(n), do: trunc(n * 1024 * 1024)
end

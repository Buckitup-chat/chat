defmodule Chat.ChunkedFilesTest do
  use ExUnit.Case, async: false

  alias Chat.ChunkedFiles

  test "should generate a key and a secret on upload start, save chunks by key and able to read full file decrypting with secret" do
    {key, secret} = ChunkedFiles.new_upload()

    assert 24 = byte_size(secret)

    first = "some part of info "
    second = "another part"

    ChunkedFiles.save_upload_chunk(key, {1, 18}, first)
    assert false == ChunkedFiles.complete_upload?(key, 30)

    ChunkedFiles.save_upload_chunk(key, {19, 30}, second)
    assert ChunkedFiles.complete_upload?(key, 30)

    recovered = ChunkedFiles.read({key, secret})

    assert recovered == Enum.join([first, second])
  end

  test "should forget key" do
    {key, _secret} = ChunkedFiles.new_upload()
    assert nil != Chat.ChunkedFilesBroker.get(key)

    ChunkedFiles.mark_consumed(key)
    assert nil == Chat.ChunkedFilesBroker.get(key)
  end
end

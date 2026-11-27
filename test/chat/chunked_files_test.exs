defmodule Chat.ChunkedFilesTest do
  use ExUnit.Case, async: true, group: :cubdb

  import Rewire

  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesBroker
  alias Chat.Db.ChangeTracker
  alias Chat.FileFs
  alias Chat.Identity

  defmodule DbMock do
    def put_chunk(_data) do
      [result | rest] = Process.get(:put_chunk_results)
      Process.put(:put_chunk_results, rest)
      result
    end

    def put(key, value), do: send(self(), {:db_put, key, value})

    defdelegate bulk_delete(range), to: Chat.Db
    defdelegate list(range), to: Chat.Db
  end

  defmodule FileFsNeverStored do
    def has_file?(_keys) do
      Process.put(:has_file_checks, Process.get(:has_file_checks, 0) + 1)
      false
    end

    defdelegate count_size_stored(key), to: Chat.FileFs
    defdelegate delete_file(key), to: Chat.FileFs
    defdelegate file_size(key), to: Chat.FileFs
    defdelegate read_file_chunk(first, key), to: Chat.FileFs
    defdelegate stream_file_chunks(key), to: Chat.FileFs
  end

  defmodule FileFsRaising do
    def file_size(_key), do: raise(File.Error, reason: :enoent, action: "list", path: "x")

    defdelegate count_size_stored(key), to: Chat.FileFs
    defdelegate delete_file(key), to: Chat.FileFs
    defdelegate has_file?(keys), to: Chat.FileFs
    defdelegate read_file_chunk(first, key), to: Chat.FileFs
    defdelegate stream_file_chunks(key), to: Chat.FileFs
  end

  defmodule NoSleep do
    def sleep(_ms), do: :ok
  end

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

  test "resume_upload stores an existing secret and get_file retrieves it" do
    key = UUID.uuid4() |> Enigma.hash()
    secret = Enigma.generate_secret()

    ChunkedFiles.resume_upload(key, secret)

    assert secret == ChunkedFiles.get_file(key)
  end

  test "next_chunk returns 0 before any upload and increases as chunks are saved" do
    key = UUID.uuid4() |> Enigma.hash()
    _secret = ChunkedFiles.new_upload(key)

    assert 0 == ChunkedFiles.next_chunk(key)

    ChunkedFiles.save_upload_chunk(key, {0, 9}, 20, "first part")
    ChangeTracker.await()
    assert 1 == ChunkedFiles.next_chunk(key)

    ChunkedFiles.save_upload_chunk(key, {10, 19}, 20, "2nd.parts!")
    ChangeTracker.await()
    assert 2 == ChunkedFiles.next_chunk(key)
  end

  test "save_upload_chunk returns error when no upload session exists for key" do
    key = UUID.uuid4() |> Enigma.hash()

    assert {:empty_initial_secret, true} ==
             ChunkedFiles.save_upload_chunk(key, {0, 9}, 10, "data")
  end

  test "delete removes stored chunks and forgets the broker key" do
    key = UUID.uuid4() |> Enigma.hash()
    _secret = ChunkedFiles.new_upload(key)

    ChunkedFiles.save_upload_chunk(key, {0, 9}, 10, "some data!")
    assert nil != ChunkedFilesBroker.get(key)

    ChunkedFiles.delete(key)

    assert nil == ChunkedFilesBroker.get(key)
    assert 0 == ChunkedFiles.size(key)
  end

  test "size returns the byte size of a stored file" do
    key = UUID.uuid4() |> Enigma.hash()
    data = "hello world"
    _secret = ChunkedFiles.new_upload(key)
    ChunkedFiles.save_upload_chunk(key, {0, byte_size(data) - 1}, byte_size(data), data)

    assert byte_size(data) == ChunkedFiles.size(key)
  end

  test "chunk_with_byterange reads first chunk using default range" do
    key = UUID.uuid4() |> Enigma.hash()
    secret = ChunkedFiles.new_upload(key)
    data = "hello world"
    ChunkedFiles.save_upload_chunk(key, {0, byte_size(data) - 1}, byte_size(data), data)

    {{0, last}, chunk} = ChunkedFiles.chunk_with_byterange({key, secret})

    assert last == byte_size(data) - 1
    assert chunk == data
  end

  test "chunk_with_byterange with {first, nil} reads from offset to end of chunk" do
    key = UUID.uuid4() |> Enigma.hash()
    secret = ChunkedFiles.new_upload(key)
    data = "hello world"
    ChunkedFiles.save_upload_chunk(key, {0, byte_size(data) - 1}, byte_size(data), data)

    {{3, last}, chunk} = ChunkedFiles.chunk_with_byterange({key, secret}, {3, nil})

    assert last == byte_size(data) - 1
    assert chunk == binary_part(data, 3, byte_size(data) - 3)
  end

  test "chunk_with_byterange with explicit range returns sliced data" do
    key = UUID.uuid4() |> Enigma.hash()
    secret = ChunkedFiles.new_upload(key)
    data = "hello world"
    ChunkedFiles.save_upload_chunk(key, {0, byte_size(data) - 1}, byte_size(data), data)

    {{2, 5}, chunk} = ChunkedFiles.chunk_with_byterange({key, secret}, {2, 5})

    assert chunk == binary_part(data, 2, 4)
  end

  test "encrypt_secret and decrypt_secret are inverse operations" do
    me = Identity.create("test_user")
    secret = Enigma.generate_secret()

    encrypted = ChunkedFiles.encrypt_secret(secret, me)
    decrypted = ChunkedFiles.decrypt_secret(encrypted, me)

    assert decrypted == secret
    assert encrypted != secret
  end

  describe "chunk write verification" do
    setup do
      key = UUID.uuid4() |> Enigma.hash()
      _secret = ChunkedFiles.new_upload(key)

      %{key: key}
    end

    test "fails after all checks and the retry find no chunk on disk", %{key: key} do
      Process.put(:put_chunk_results, [:ok, :ok])

      rewire ChunkedFiles, Db: DbMock, FileFs: FileFsNeverStored, Process: NoSleep do
        assert :failed_to_check_file == ChunkedFiles.save_upload_chunk(key, {0, 3}, 4, "data")
      end

      assert 12 == Process.get(:has_file_checks)
      refute_received {:db_put, _, _}
    end

    test "returns the retry write error", %{key: key} do
      Process.put(:put_chunk_results, [:ok, {:error, :queue_down}])

      rewire ChunkedFiles, Db: DbMock, FileFs: FileFsNeverStored, Process: NoSleep do
        assert {:error, :queue_down} == ChunkedFiles.save_upload_chunk(key, {0, 3}, 4, "data")
      end

      assert 7 == Process.get(:has_file_checks)
      refute_received {:db_put, _, _}
    end
  end

  test "size is 0 when the file size can't be read" do
    rewire ChunkedFiles, FileFs: FileFsRaising do
      assert 0 == ChunkedFiles.size("missing")
    end
  end

  defp mb(n) when is_integer(n), do: n * 1024 * 1024
  defp mb(n), do: trunc(n * 1024 * 1024)
end

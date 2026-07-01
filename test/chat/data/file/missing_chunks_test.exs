defmodule Chat.Data.File.MissingChunksTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.File, as: FileData
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Types.FileId

  describe "insert_missing_chunks_placeholders/5" do
    test "inserts placeholder rows for each chunk index" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 3, "http://peer:4444", 1_000_000)

      chunks = Repo.all(from(m in MissingChunk, where: m.file_id == ^file_id, order_by: m.chunk_index))
      assert length(chunks) == 3
      assert Enum.map(chunks, & &1.chunk_index) == [0, 1, 2]
      assert Enum.all?(chunks, &is_nil(&1.data_hash))
      assert Enum.all?(chunks, &(&1.peer_url == "http://peer:4444"))
      assert Enum.all?(chunks, &(&1.attempts == 0))
    end

    test "with source_drive_id option" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000,
        source_drive_id: "usb_drive_1"
      )

      chunk = Repo.one!(from(m in MissingChunk, where: m.file_id == ^file_id))
      assert chunk.source_drive_id == "usb_drive_1"
      assert is_nil(chunk.peer_url)
    end

    test "on_conflict :nothing skips duplicates" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 2, "http://peer:4444", 1_000_000)
      FileData.insert_missing_chunks_placeholders(file_id, 2, "http://peer:4444", 2_000_000)

      assert Repo.aggregate(
               from(m in MissingChunk, where: m.file_id == ^file_id),
               :count
             ) == 2
    end
  end

  describe "fill_missing_chunk/5" do
    test "sets data_hash and size on an existing placeholder" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000)
      FileData.fill_missing_chunk(file_id, 0, data_hash, 4096)

      chunk = Repo.one!(from(m in MissingChunk, where: m.file_id == ^file_id))
      assert chunk.data_hash == data_hash
      assert chunk.size == 4096
    end
  end

  describe "delete_missing_chunk/3" do
    test "removes a specific chunk" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 3, nil, 1_000_000)
      FileData.delete_missing_chunk(file_id, 1)

      remaining = Repo.all(from(m in MissingChunk, where: m.file_id == ^file_id))
      assert length(remaining) == 2
      refute 1 in Enum.map(remaining, & &1.chunk_index)
    end
  end

  describe "delete_missing_chunks_for_file/1" do
    test "removes all chunks for a file" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 5, nil, 1_000_000)
      FileData.delete_missing_chunks_for_file(file_id)

      assert Repo.aggregate(
               from(m in MissingChunk, where: m.file_id == ^file_id),
               :count
             ) == 0
    end
  end

  describe "increment_missing_chunk_attempts/4" do
    test "increments attempts and updates timestamp" do
      file_id = FileId.generate()

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000)
      FileData.increment_missing_chunk_attempts(file_id, 0, 2_000_000)

      chunk = Repo.one!(from(m in MissingChunk, where: m.file_id == ^file_id))
      assert chunk.attempts == 1
      assert chunk.updated_at == 2_000_000

      FileData.increment_missing_chunk_attempts(file_id, 0, 3_000_000)

      chunk = Repo.one!(from(m in MissingChunk, where: m.file_id == ^file_id))
      assert chunk.attempts == 2
    end
  end

  describe "missing_chunk_count/1" do
    test "returns count of missing chunks for a file" do
      file_id = FileId.generate()

      assert FileData.missing_chunk_count(file_id) == 0

      FileData.insert_missing_chunks_placeholders(file_id, 4, nil, 1_000_000)
      assert FileData.missing_chunk_count(file_id) == 4
    end
  end

  describe "get_missing_chunk_hash/3" do
    test "returns data_hash for a specific chunk" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("cd", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000)
      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)

      assert FileData.get_missing_chunk_hash(file_id, 0) == data_hash
    end

    test "returns nil when chunk not found" do
      assert FileData.get_missing_chunk_hash(FileId.generate(), 0) == nil
    end
  end

  describe "fetchable_missing_chunks_for_sync/3" do
    test "returns only chunks with data_hash set" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 3, "http://peer:4444", 1_000_000)
      FileData.fill_missing_chunk(file_id, 1, data_hash, 100)

      result = FileData.fetchable_missing_chunks_for_sync(10, nil)
      assert length(result) == 1
      assert hd(result).chunk_index == 1
    end

    test "orders by attempts ascending" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 2, nil, 1_000_000)
      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)
      FileData.fill_missing_chunk(file_id, 1, data_hash, 100)
      FileData.increment_missing_chunk_attempts(file_id, 0, 2_000_000)

      result = FileData.fetchable_missing_chunks_for_sync(10, nil)
      assert hd(result).chunk_index == 1
    end

    test "respects max_attempts when provided" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000)
      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)
      FileData.increment_missing_chunk_attempts(file_id, 0, 2_000_000)

      assert FileData.fetchable_missing_chunks_for_sync(10, 1) == []
      assert length(FileData.fetchable_missing_chunks_for_sync(10, 2)) == 1
    end

    test "respects limit" do
      for i <- 0..4 do
        file_id = FileId.generate()
        data_hash = "fd_" <> String.duplicate("ab", 64)
        FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000 + i)
        FileData.fill_missing_chunk(file_id, 0, data_hash, 100)
      end

      assert length(FileData.fetchable_missing_chunks_for_sync(3, nil)) == 3
    end
  end

  describe "fetchable_missing_chunks_for_copy/3" do
    test "returns chunks with data_hash set and under max attempts" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 2, nil, 1_000_000,
        source_drive_id: "usb1"
      )

      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)

      result = FileData.fetchable_missing_chunks_for_copy(10, 10)
      assert length(result) == 1
      assert hd(result).source_drive_id == "usb1"
    end
  end

  describe "missing_chunks_for_peer/2" do
    test "returns fetchable chunks for a specific peer" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 2, "http://peer:4444", 1_000_000)
      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)
      FileData.fill_missing_chunk(file_id, 1, data_hash, 100)

      result = FileData.missing_chunks_for_peer("http://peer:4444")
      assert length(result) == 2

      assert FileData.missing_chunks_for_peer("http://other:4444") == []
    end
  end

  describe "missing_chunks_for_drive/2" do
    test "returns fetchable chunks for a specific drive" do
      file_id = FileId.generate()
      data_hash = "fd_" <> String.duplicate("ab", 64)

      FileData.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000,
        source_drive_id: "usb1"
      )

      FileData.fill_missing_chunk(file_id, 0, data_hash, 100)

      result = FileData.missing_chunks_for_drive("usb1")
      assert length(result) == 1

      assert FileData.missing_chunks_for_drive("usb_other") == []
    end
  end
end

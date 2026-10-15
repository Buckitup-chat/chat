defmodule Chat.Data.File.ChunkPresenceTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.File.ChunkPresence
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.FileId

  @data_hash "fd_" <> String.duplicate("ab", 64)
  @uploader_hash "u_" <> String.duplicate("cd", 64)

  setup do
    %UserCard{
      user_hash: @uploader_hash,
      sign_pkey: "pkey",
      contact_pkey: "cpkey",
      contact_cert: "ccert",
      crypt_pkey: "crpkey",
      crypt_cert: "crcert",
      name: "test",
      deleted_flag: false,
      owner_timestamp: 1_000_000,
      sign_b64: "sig"
    }
    |> Ecto.Changeset.change()
    |> Repo.insert!()

    :ok
  end

  defp insert_file_chunk(file_id, chunk_index) do
    %FileChunk{
      file_id: file_id,
      chunk_index: chunk_index,
      data_hash: @data_hash,
      size: 4096,
      uploader_hash: @uploader_hash,
      owner_timestamp: 1_000_000,
      sign_b64: "sig"
    }
    |> Ecto.Changeset.change()
    |> Repo.insert!()
  end

  describe "present_chunk_keys/1" do
    test "returns keys for file_chunks with data_hash and no missing_chunk row" do
      file_id = FileId.generate()
      insert_file_chunk(file_id, 0)

      assert {file_id, 0} in ChunkPresence.present_chunk_keys()
    end

    # data_hash has a NOT NULL constraint in the DB, so nil data_hash
    # cannot occur; the query guard is retained for safety but untestable.

    test "excludes chunks that have a MissingChunk row" do
      file_id = FileId.generate()
      insert_file_chunk(file_id, 0)

      Chat.Data.File.insert_missing_chunks_placeholders(file_id, 1, nil, 1_000_000)

      keys = ChunkPresence.present_chunk_keys()
      refute Enum.any?(keys, fn {fid, _} -> fid == file_id end)
    end
  end

  describe "missing_chunk_keys/1" do
    test "returns all missing chunk keys" do
      file_id = FileId.generate()

      Chat.Data.File.insert_missing_chunks_placeholders(file_id, 3, nil, 1_000_000)

      keys = ChunkPresence.missing_chunk_keys()
      assert {file_id, 0} in keys
      assert {file_id, 1} in keys
      assert {file_id, 2} in keys
    end
  end

  describe "backfill_missing_from_file_chunks/3" do
    test "inserts rows with the given source_drive_id and returns the count" do
      file_id = FileId.generate()
      insert_file_chunk(file_id, 0)
      insert_file_chunk(file_id, 1)

      count = ChunkPresence.backfill_missing_from_file_chunks("drive_a", 2_000_000)

      assert count == 2

      missing = ChunkPresence.missing_chunk_keys()
      assert {file_id, 0} in missing
      assert {file_id, 1} in missing
    end

    test "a second call inserts 0" do
      file_id = FileId.generate()
      insert_file_chunk(file_id, 0)

      assert ChunkPresence.backfill_missing_from_file_chunks("drive_a", 2_000_000) == 1
      assert ChunkPresence.backfill_missing_from_file_chunks("drive_a", 3_000_000) == 0
    end
  end
end

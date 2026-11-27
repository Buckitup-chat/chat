defmodule Chat.Data.File.GCTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.GC
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Schemas.UploadChunk
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo
  alias Chat.Storage.Default
  alias Chat.TimeKeeper
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    identity = User.generate_pq_identity("Alice")
    card = signed_user_card(identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    {:ok, identity: identity, user_hash: card.user_hash}
  end

  describe "handle_info(:gc)" do
    test "purges chunk rows, missing chunks and stored blobs of deleted files", ctx do
      file = insert_file_with_chunk(ctx.identity, ctx.user_hash)
      FileData.insert_missing_chunks_placeholders(file.file_id, 3, nil, 1_000_000)
      :ok = ChunkStore.put(Default.unit(), file.file_id, 0, "chunk data")
      soft_delete_file(file, ctx.identity.sign_skey)

      run_gc()

      assert chunk_count(file.file_id) == 0
      assert missing_count(file.file_id) == 0
      assert {:error, :enoent} = ChunkStore.fetch(Default.unit(), file.file_id, 0)
    end

    test "purges deleted file chunks beyond a single batch", ctx do
      file = insert_file_with_chunk(ctx.identity, ctx.user_hash)
      insert_raw_chunks(file.file_id, 1..120, ctx.user_hash)
      soft_delete_file(file, ctx.identity.sign_skey)
      assert chunk_count(file.file_id) == 121

      run_gc()

      assert chunk_count(file.file_id) == 0
    end

    test "purges stale uploads with their orphan chunks and blobs", ctx do
      file_id = FileId.generate()
      insert_raw_chunks(file_id, [0], ctx.user_hash)
      insert_upload_chunk(file_id, ctx.user_hash, _stale = 1_000_000)
      FileData.insert_missing_chunks_placeholders(file_id, 2, nil, 1_000_000)
      :ok = ChunkStore.put(Default.unit(), file_id, 0, "upload data")

      run_gc()

      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) == nil
      assert chunk_count(file_id) == 0
      assert missing_count(file_id) == 0
      assert {:error, :enoent} = ChunkStore.fetch(Default.unit(), file_id, 0)
    end

    test "keeps live files, fresh uploads and committed uploads", ctx do
      live = insert_file_with_chunk(ctx.identity, ctx.user_hash)
      :ok = ChunkStore.put(Default.unit(), live.file_id, 0, "live data")
      on_exit(fn -> ChunkStore.delete_file(Default.unit(), live.file_id) end)

      fresh_id = FileId.generate()
      insert_raw_chunks(fresh_id, [0], ctx.user_hash)
      insert_upload_chunk(fresh_id, ctx.user_hash, TimeKeeper.now_unix())

      committed = insert_file_with_chunk(ctx.identity, ctx.user_hash)
      insert_upload_chunk(committed.file_id, ctx.user_hash, _stale = 1_000_000)

      run_gc()

      assert chunk_count(live.file_id) == 1
      assert {:ok, "live data"} = ChunkStore.fetch(Default.unit(), live.file_id, 0)
      assert Repo.get_by(UploadChunk, file_id: fresh_id, chunk_index: 0)
      assert chunk_count(fresh_id) == 1
      assert Repo.get_by(UploadChunk, file_id: committed.file_id, chunk_index: 0)
      assert chunk_count(committed.file_id) == 1
    end

    test "ignores unknown messages and stays alive" do
      pid = start_gc()
      send(pid, :unexpected)

      assert %{} = :sys.get_state(pid)
    end
  end

  defp start_gc do
    pid = start_supervised!({GC, name: nil})
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  defp run_gc do
    pid = start_gc()
    send(pid, :gc)
    :sys.get_state(pid)
  end

  defp chunk_count(file_id) do
    from(c in FileChunk, where: c.file_id == ^file_id)
    |> Repo.aggregate(:count)
  end

  defp missing_count(file_id) do
    from(m in MissingChunk, where: m.file_id == ^file_id)
    |> Repo.aggregate(:count)
  end

  defp insert_raw_chunks(file_id, indexes, user_hash) do
    rows =
      Enum.map(indexes, fn index ->
        %{
          file_id: file_id,
          chunk_index: index,
          data_hash: :crypto.strong_rand_bytes(64) |> FileChunkDataHash.from_binary(),
          size: 100,
          uploader_hash: user_hash,
          owner_timestamp: System.os_time(:millisecond),
          sign_b64: :crypto.strong_rand_bytes(64)
        }
      end)

    Repo.insert_all(FileChunk, rows)
  end

  defp insert_file_with_chunk(identity, user_hash) do
    file = signed_file(identity, user_hash)
    {:ok, _} = ShapeWriter.write(:file, :insert, file)

    chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)
    {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)

    file
  end

  defp soft_delete_file(file, sign_skey) do
    deleted =
      signed_file_from(file, sign_skey, %{
        deleted_flag: true,
        chunk_sign_hashes: [],
        owner_timestamp: file.owner_timestamp + 1
      })

    {:ok, _} = ShapeWriter.write(:file, :update, deleted)
  end

  defp insert_upload_chunk(file_id, user_hash, updated_at) do
    Repo.insert!(%UploadChunk{
      file_id: file_id,
      chunk_index: 0,
      chunk_sign_hash: :crypto.strong_rand_bytes(64),
      uploader_hash: user_hash,
      size: 100,
      updated_at: updated_at
    })
  end

  # Helpers

  defp signed_user_card(identity) do
    card = User.extract_pq_card(identity)
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end

  defp signed_file(identity, user_hash, attrs \\ %{}) do
    chunk_sign_hash = EnigmaPq.hash(:crypto.strong_rand_bytes(100))

    file =
      %FileSchema{
        file_id: FileId.generate(),
        uploader_hash: user_hash,
        total_size: 4_194_304,
        chunk_size: 4_194_304,
        chunk_count: 1,
        chunk_sign_hashes: [chunk_sign_hash],
        owner_timestamp: System.os_time(:millisecond),
        deleted_flag: false
      }
      |> struct(attrs)

    sign_b64 = file |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{file | sign_b64: sign_b64}
  end

  defp signed_file_from(file, sign_skey, attrs) do
    updated = struct(file, attrs)
    sign_b64 = updated |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{updated | sign_b64: sign_b64}
  end

  defp signed_file_chunk(identity, user_hash, file_id, index) do
    raw_data = :crypto.strong_rand_bytes(100)
    data_hash = raw_data |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()

    chunk = %FileChunk{
      file_id: file_id,
      chunk_index: index,
      data_hash: data_hash,
      size: byte_size(raw_data),
      uploader_hash: user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = chunk |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{chunk | sign_b64: sign_b64}
  end
end

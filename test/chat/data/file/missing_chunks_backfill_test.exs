defmodule Chat.Data.File.MissingChunksBackfillTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.MissingChunksBackfill
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Types.FileId
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup do
    identity = User.generate_pq_identity("Alice")
    card = signed_user_card(identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    tmp_dir =
      System.tmp_dir!()
      |> Path.join("backfill_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, identity: identity, user_hash: card.user_hash, base_dir: tmp_dir}
  end

  describe "run/1" do
    test "inserts missing_chunks for file_chunks not on disk", ctx do
      file = insert_file(ctx)
      insert_chunk(ctx, file.file_id, 0)
      insert_chunk(ctx, file.file_id, 1)

      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)

      missing =
        Repo.all(
          from(m in MissingChunk,
            where: m.file_id == ^file.file_id,
            order_by: m.chunk_index
          )
        )

      assert length(missing) == 2
      assert Enum.map(missing, & &1.chunk_index) == [0, 1]
    end

    test "skips chunks already on disk", ctx do
      file = insert_file(ctx)
      insert_chunk(ctx, file.file_id, 0)
      insert_chunk(ctx, file.file_id, 1)

      :ok = ChunkStore.put(file.file_id, 0, "data on disk", ctx.base_dir)

      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)

      missing =
        Repo.all(from(m in MissingChunk, where: m.file_id == ^file.file_id))

      assert length(missing) == 1
      assert hd(missing).chunk_index == 1
    end

    test "preserves data_hash and size from file_chunks", ctx do
      file = insert_file(ctx)
      chunk = insert_chunk(ctx, file.file_id, 0)

      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)

      missing = Repo.one!(from(m in MissingChunk, where: m.file_id == ^file.file_id))
      assert missing.data_hash == chunk.data_hash
      assert missing.size == chunk.size
    end

    test "skips deleted files", ctx do
      file = insert_file(ctx)
      insert_chunk(ctx, file.file_id, 0)
      soft_delete_file(file, ctx.identity.sign_skey)

      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)

      assert Repo.aggregate(
               from(m in MissingChunk, where: m.file_id == ^file.file_id),
               :count
             ) == 0
    end

    test "does not duplicate on repeated runs", ctx do
      file = insert_file(ctx)
      insert_chunk(ctx, file.file_id, 0)

      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)
      MissingChunksBackfill.run(repo: Repo, base_dir: ctx.base_dir)

      assert Repo.aggregate(
               from(m in MissingChunk, where: m.file_id == ^file.file_id),
               :count
             ) == 1
    end

    test "does nothing when no files exist", _ctx do
      MissingChunksBackfill.run(repo: Repo, base_dir: "/nonexistent")

      assert Repo.aggregate(MissingChunk, :count) == 0
    end
  end

  # Helpers

  defp insert_file(%{identity: identity, user_hash: user_hash}) do
    file = signed_file(identity, user_hash)
    {:ok, _} = ShapeWriter.write(:file, :insert, file)
    file
  end

  defp insert_chunk(%{identity: identity, user_hash: user_hash}, file_id, index) do
    chunk = signed_file_chunk(identity, user_hash, file_id, index)
    {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)
    chunk
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

  defp signed_user_card(identity) do
    card = User.extract_pq_card(identity)
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end

  defp signed_file(identity, user_hash) do
    chunk_sign_hash = EnigmaPq.hash(:crypto.strong_rand_bytes(100))

    file = %FileSchema{
      file_id: FileId.generate(),
      uploader_hash: user_hash,
      total_size: 4_194_304,
      chunk_size: 4_194_304,
      chunk_count: 1,
      chunk_sign_hashes: [chunk_sign_hash],
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

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
    data_hash = raw_data |> EnigmaPq.hash() |> Chat.Data.Types.FileChunkDataHash.from_binary()

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

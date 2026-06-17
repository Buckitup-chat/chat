defmodule Chat.Data.File.GCTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.File, as: FileData
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UploadChunk
  alias Chat.Data.Types.FileId
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  setup do
    identity = User.generate_pq_identity("Alice")
    card = signed_user_card(identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    {:ok, identity: identity, user_hash: card.user_hash}
  end

  describe "gc_deleted_files" do
    test "deletes file_chunks for deleted files", %{identity: identity, user_hash: user_hash} do
      file = insert_file_with_chunk(identity, user_hash)
      soft_delete_file(file, identity.sign_skey)

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) != nil

      FileData.deleted_file_ids_with_chunks()
      |> Enum.each(&FileData.delete_file_chunks_batch(&1, 50))

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) == nil
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
  end

  describe "gc_stale_uploads" do
    test "deletes stale upload_chunks and orphan file_chunks", %{
      identity: identity,
      user_hash: user_hash
    } do
      file_id = FileId.generate()
      chunk = insert_orphan_chunk(identity, user_hash, file_id)
      insert_upload_chunk_record(file_id, 0, chunk, user_hash, _stale_timestamp = 1_000_000)

      stale_ids = FileData.stale_upload_chunk_file_ids(2_000_000)
      assert file_id in stale_ids

      Enum.each(stale_ids, &FileData.delete_upload_chunks_for_file/1)
      Enum.each(stale_ids, &FileData.delete_file_chunks_batch(&1, 50))

      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) == nil
      assert Repo.get_by(FileChunk, file_id: file_id, chunk_index: 0) == nil
    end

    test "does not delete upload_chunks for committed files", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      insert_upload_chunk_record(file.file_id, 0, nil, user_hash, _stale_timestamp = 1_000_000)

      stale_ids = FileData.stale_upload_chunk_file_ids(2_000_000)
      refute file.file_id in stale_ids
    end

    defp insert_orphan_chunk(identity, user_hash, file_id) do
      chunk = signed_file_chunk(identity, user_hash, file_id, 0)
      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)
      chunk
    end

    defp insert_upload_chunk_record(file_id, index, chunk, user_hash, updated_at) do
      Repo.insert!(%UploadChunk{
        file_id: file_id,
        chunk_index: index,
        chunk_sign_hash:
          if(chunk, do: EnigmaPq.hash(chunk.sign_b64), else: :crypto.strong_rand_bytes(64)),
        uploader_hash: user_hash,
        size: if(chunk, do: chunk.size, else: 100),
        updated_at: updated_at
      })
    end
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
    data_hash = raw_data |> EnigmaPq.hash() |> Chat.Data.Types.FileChunkDataHash.from_binary()

    chunk = %FileChunk{
      file_id: file_id,
      chunk_index: index,
      cid: cidv1_raw(raw_data),
      data_hash: data_hash,
      size: byte_size(raw_data),
      uploader_hash: user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = chunk |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{chunk | sign_b64: sign_b64}
  end

  defp cidv1_raw(data) do
    digest = :crypto.hash(:sha256, data)
    "b" <> Base.encode32(<<1, 0x55, 0x12, 0x20>> <> digest, case: :lower, padding: false)
  end
end

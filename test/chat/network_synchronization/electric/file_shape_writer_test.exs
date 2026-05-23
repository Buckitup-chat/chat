defmodule Chat.NetworkSynchronization.Electric.FileShapeWriterTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Types.FileId
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.DeferredStore
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    identity = User.generate_pq_identity("Alice")
    card = signed_user_card(identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

    {:ok, identity: identity, user_hash: card.user_hash}
  end

  describe "file (manifest)" do
    test "insert writes a new row", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)

      assert {:ok, _} = ShapeWriter.write(:file, :insert, file)
      assert Repo.get(FileSchema, file.file_id) != nil
    end

    test "insert with newer timestamp upserts", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      newer =
        signed_file(identity, user_hash, %{
          file_id: file.file_id,
          total_size: 9999,
          owner_timestamp: file.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:file, :insert, newer)

      assert Repo.get(FileSchema, file.file_id).total_size == 9999
    end

    test "insert with same timestamp is skipped", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      same_ts =
        signed_file(identity, user_hash, %{
          file_id: file.file_id,
          total_size: 9999,
          owner_timestamp: file.owner_timestamp
        })

      {:ok, _} = ShapeWriter.write(:file, :insert, same_ts)

      assert Repo.get(FileSchema, file.file_id).total_size == file.total_size
    end

    test "update sets deleted_flag", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      deleted =
        signed_file_from(file, identity.sign_skey, %{
          deleted_flag: true,
          chunk_sign_hashes: [],
          owner_timestamp: file.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:file, :update, deleted)

      stored = Repo.get(FileSchema, file.file_id)
      assert stored.deleted_flag == true
      assert stored.chunk_sign_hashes == []
    end

    test "insert without parent user_card is deferred", %{identity: identity} do
      other_identity = User.generate_pq_identity("Ghost")
      other_card = User.extract_pq_card(other_identity)
      file = signed_file(other_identity, other_card.user_hash)

      assert {:ok, :skipped_no_parent} =
               ShapeWriter.write(:file, :insert, file, peer_url: "http://peer:4444")

      assert [record] = DeferredStore.check_children(:user_card, other_card.user_hash)
      assert record.shape == :file
    end
  end

  describe "file_chunk" do
    test "insert writes a new row when parent file exists", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)
      assert {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) != nil
    end

    test "insert is idempotent — on_conflict nothing", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)
      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)
      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)

      count =
        Repo.aggregate(
          Ecto.Query.from(c in FileChunk, where: c.file_id == ^file.file_id),
          :count
        )

      assert count == 1
    end

    test "insert without parent file is deferred", %{identity: identity, user_hash: user_hash} do
      file_id = FileId.generate()
      chunk = signed_file_chunk(identity, user_hash, file_id, 0)

      assert {:ok, :skipped_no_parent} =
               ShapeWriter.write(:file_chunk, :insert, chunk, peer_url: "http://peer:4444")

      assert [record] = DeferredStore.check_children(:file, file_id)
      assert record.shape == :file_chunk
    end

    test "insert rejected when parent uploader_hash mismatches", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      other_identity = User.generate_pq_identity("Eve")
      other_card = signed_user_card(other_identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, other_card)

      chunk = signed_file_chunk(other_identity, other_card.user_hash, file.file_id, 0)

      assert {:error, {:rejected, :uploader_mismatch}} =
               ShapeWriter.write(:file_chunk, :insert, chunk)
    end

    test "insert rejected when parent file is deleted", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      deleted =
        signed_file_from(file, identity.sign_skey, %{
          deleted_flag: true,
          chunk_sign_hashes: [],
          owner_timestamp: file.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:file, :update, deleted)

      chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)

      assert {:error, {:rejected, :file_deleted}} =
               ShapeWriter.write(:file_chunk, :insert, chunk)
    end
  end

  # --- Helpers ---

  defp signed_user_card(identity, attrs \\ %{}) do
    card = identity |> User.extract_pq_card() |> struct(attrs)
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end

  defp signed_file(identity, user_hash, attrs \\ %{}) do
    chunk_data = :crypto.strong_rand_bytes(100)
    chunk_sign_hash = EnigmaPq.hash(chunk_data)

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
    data_b64 = :crypto.strong_rand_bytes(100)

    chunk = %FileChunk{
      file_id: file_id,
      chunk_index: index,
      data_b64: data_b64,
      size: byte_size(data_b64),
      uploader_hash: user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = chunk |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{chunk | sign_b64: sign_b64}
  end
end

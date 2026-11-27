defmodule Chat.Data.Shapes.FileSyncTest do
  @moduledoc """
  Peer-sync callbacks of the `file` and `file_chunk` shapes, called directly
  (the way `ShapeWriter` does): bytea decoding fallbacks, rejected updates,
  parent validation and the missing-chunk bookkeeping done after persist.
  """
  use ChatWeb.DataCase, async: true

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]
  import ExUnit.CaptureLog
  import Rewire

  alias Chat.Data.File, as: FileData
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Shapes
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId
  alias Chat.Data.User

  @peer_url "http://peer:4444"

  defmodule SyncSourceSpy do
    def chunk_fetchable(drive_id, file_id, chunk_index, peer_url),
      do: send(self(), {:chunk_fetchable, drive_id, file_id, chunk_index, peer_url})
  end

  # the real SyncSource would try to fetch from the fake peer outside the sandbox
  rewire(Chat.Data.Shapes.FileChunk, SyncSource: SyncSourceSpy, as: FileChunkShape)

  setup do
    identity = User.generate_pq_identity("Uploader")
    card = insert_user_card(identity)

    {:ok, identity: identity, user_hash: card.user_hash}
  end

  describe "File.sync_derive_fields/1" do
    test "keeps a hex-looking value that is not valid hex" do
      file = %FileSchema{chunk_sign_hashes: ["\\\\xZZ"], sign_b64: "\\\\xnot-hex"}

      assert %{chunk_sign_hashes: ["\\\\xZZ"], sign_b64: "\\\\xnot-hex"} =
               Shapes.File.sync_derive_fields(file)
    end

    test "keeps a binary that is not valid base64" do
      file = %FileSchema{chunk_sign_hashes: ["*not base64*"], sign_b64: "*nope*"}

      assert %{chunk_sign_hashes: ["*not base64*"], sign_b64: "*nope*"} =
               Shapes.File.sync_derive_fields(file)
    end

    test "decodes base64 values" do
      file = %FileSchema{
        chunk_sign_hashes: [Base.encode64("hash")],
        sign_b64: Base.encode64("sig")
      }

      assert %{chunk_sign_hashes: ["hash"], sign_b64: "sig"} =
               Shapes.File.sync_derive_fields(file)
    end

    test "passes non-binary values through" do
      file = %FileSchema{chunk_sign_hashes: [nil], sign_b64: nil}

      assert %{chunk_sign_hashes: [nil], sign_b64: nil} = Shapes.File.sync_derive_fields(file)
    end
  end

  describe "File.sync_persist(:update, _)" do
    test "skips an update for an unknown file", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)

      assert {:ok, ^file} = Shapes.File.sync_persist(:update, file)
      refute FileData.get_file(file.file_id)
    end

    test "rejects an update with a forged signature", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)
      {:ok, _} = Shapes.File.sync_persist(:insert, file)

      forged =
        %{
          file
          | deleted_flag: true,
            chunk_sign_hashes: [],
            owner_timestamp: file.owner_timestamp + 1
        }

      log =
        capture_log(fn ->
          assert {:ok, ^forged} = Shapes.File.sync_persist(:update, forged)
        end)

      assert log =~ "Invalid file update signature"
      assert %{deleted_flag: false} = FileData.get_file(file.file_id)
    end
  end

  describe "File.sync_after_persist/3" do
    test "preseeds missing-chunk placeholders when synced from a peer", %{
      identity: identity,
      user_hash: user_hash
    } do
      file = signed_file(identity, user_hash, chunk_count: 2)

      assert :ok = Shapes.File.sync_after_persist(:insert, file, peer_url: @peer_url)

      assert [%{chunk_index: 0, peer_url: @peer_url}, %{chunk_index: 1, peer_url: @peer_url}] =
               missing_chunks(file.file_id)
    end

    test "does nothing without a peer url", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)

      assert :ok = Shapes.File.sync_after_persist(:insert, file, [])
      assert [] = missing_chunks(file.file_id)
    end
  end

  describe "FileChunk.sync_validate_parent/2" do
    test "rejects a chunk whose file is unknown", %{identity: identity, user_hash: user_hash} do
      chunk = signed_chunk(identity, user_hash, FileId.generate())

      assert {:reject, :file_not_found} =
               Shapes.FileChunk.sync_validate_parent({:file, chunk.file_id}, chunk)
    end
  end

  describe "FileChunk.sync_after_persist/3" do
    test "fills the placeholder and reports the chunk fetchable when synced from a peer", %{
      identity: identity,
      user_hash: user_hash
    } do
      file_id = FileId.generate()
      FileData.insert_missing_chunks_placeholders(file_id, 1, @peer_url, 1_000_000)
      chunk = signed_chunk(identity, user_hash, file_id)

      assert :ok = FileChunkShape.sync_after_persist(:insert, chunk, peer_url: @peer_url)

      assert [%{data_hash: data_hash, size: size}] = missing_chunks(file_id)
      assert data_hash == chunk.data_hash
      assert size == chunk.size
      assert_received {:chunk_fetchable, _drive_id, ^file_id, 0, @peer_url}
    end
  end

  # Helpers

  defp signed_file(identity, user_hash, opts \\ []) do
    %FileSchema{
      file_id: FileId.generate(),
      uploader_hash: user_hash,
      total_size: 100,
      chunk_size: 100,
      chunk_count: Keyword.get(opts, :chunk_count, 1),
      chunk_sign_hashes: [],
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }
    |> sign_with_key(identity.sign_skey)
  end

  defp signed_chunk(identity, user_hash, file_id) do
    data = :crypto.strong_rand_bytes(100)

    %FileChunk{
      file_id: file_id,
      chunk_index: 0,
      data_hash: data |> EnigmaPq.hash() |> FileChunkDataHash.from_binary(),
      size: byte_size(data),
      uploader_hash: user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }
    |> sign_with_key(identity.sign_skey)
  end

  defp missing_chunks(file_id) do
    from(m in MissingChunk, where: m.file_id == ^file_id, order_by: m.chunk_index)
    |> Repo.all()
  end
end

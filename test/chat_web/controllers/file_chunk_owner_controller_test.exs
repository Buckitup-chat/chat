defmodule ChatWeb.FileChunkOwnerControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers, only: [identity_with_card: 1]

  alias Chat.Challenge
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId
  alias Chat.Storage.Default

  setup do
    {alice, alice_card} = identity_with_card("Alice")
    {bob, bob_card} = identity_with_card("Bob")

    %{alice: {alice, alice_card}, bob: {bob, bob_card}, file_id: FileId.generate()}
  end

  describe "another uploader" do
    test "is refused on an uploaded index and on a free one", ctx do
      first = signed_chunk(ctx.alice, ctx.file_id, 0)
      assert put_chunk(ctx.conn, first).status == 200

      for index <- [0, 1] do
        conn = put_chunk(ctx.conn, signed_chunk(ctx.bob, ctx.file_id, index))

        assert conn.status == 403
        assert %{"error" => "uploader mismatch"} = Jason.decode!(conn.resp_body)
      end

      assert {:ok, first.data} == ChunkStore.fetch(Default.unit(), ctx.file_id, 0)
      refute ChunkStore.exists?(Default.unit(), ctx.file_id, 1)
    end

    test "does not stop the first upload from completing", ctx do
      chunks = Enum.map([0, 1], &signed_chunk(ctx.alice, ctx.file_id, &1))
      assert put_chunk(ctx.conn, hd(chunks)).status == 200
      assert put_chunk(ctx.conn, signed_chunk(ctx.bob, ctx.file_id, 1)).status == 403
      assert put_chunk(ctx.conn, List.last(chunks)).status == 200

      conn = post_manifest(ctx.conn, ctx.alice, ctx.file_id, chunks)

      assert conn.status == 200, conn.resp_body

      for %{index: index, data: data} <- chunks do
        assert {:ok, ^data} = ChunkStore.fetch(Default.unit(), ctx.file_id, index)
      end
    end
  end

  describe "an occupied index" do
    test "accepts the same signed chunk again without rewriting it", ctx do
      chunk = signed_chunk(ctx.alice, ctx.file_id, 0)
      assert put_chunk(ctx.conn, chunk).status == 200
      inode = chunk_inode(ctx.file_id)

      conn = put_chunk(ctx.conn, chunk)

      assert conn.status == 200
      assert chunk_inode(ctx.file_id) == inode
    end

    test "refuses a different chunk of the same uploader", ctx do
      first = signed_chunk(ctx.alice, ctx.file_id, 0)
      assert put_chunk(ctx.conn, first).status == 200

      conn = put_chunk(ctx.conn, signed_chunk(ctx.alice, ctx.file_id, 0))

      assert conn.status == 409
      assert {:ok, first.data} == ChunkStore.fetch(Default.unit(), ctx.file_id, 0)
    end
  end

  defp signed_chunk({identity, card}, file_id, index) do
    data = :crypto.strong_rand_bytes(100)

    row = %FileChunk{
      file_id: file_id,
      chunk_index: index,
      data_hash: data |> EnigmaPq.hash() |> FileChunkDataHash.from_binary(),
      size: byte_size(data),
      uploader_hash: card.user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = row |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{row: %{row | sign_b64: sign_b64}, index: index, data: data}
  end

  defp put_chunk(conn, %{row: row, data: data}) do
    conn
    |> put_req_header("x-data-hash", row.data_hash)
    |> put_req_header("x-size", to_string(row.size))
    |> put_req_header("x-uploader-hash", row.uploader_hash)
    |> put_req_header("x-owner-timestamp", to_string(row.owner_timestamp))
    |> put_req_header("x-signature", Base.encode64(row.sign_b64, padding: false))
    |> put_req_header("content-type", "application/octet-stream")
    |> put("/electric/v1/file_chunk/#{row.file_id}/#{row.chunk_index}", data)
  end

  defp post_manifest(conn, {identity, card}, file_id, chunks) do
    file = %FileSchema{
      file_id: file_id,
      uploader_hash: card.user_hash,
      total_size: length(chunks) * 100,
      chunk_size: 100,
      chunk_count: length(chunks),
      chunk_sign_hashes: Enum.map(chunks, &EnigmaPq.hash(&1.row.sign_b64)),
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    sign_b64 = file |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    {challenge_id, challenge} = Challenge.store()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => file |> manifest_fields() |> Map.put("sign_b64", b64(sign_b64)),
          "syncMetadata" => %{"relation" => "files"}
        }
      ],
      "auth" => %{
        "challenge_id" => challenge_id,
        "signature" => challenge |> EnigmaPq.sign(identity.sign_skey) |> b64()
      }
    }

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end

  defp manifest_fields(file) do
    file
    |> Map.take([:file_id, :uploader_hash, :total_size, :chunk_size, :chunk_count])
    |> Map.merge(%{
      chunk_sign_hashes: Enum.map(file.chunk_sign_hashes, &b64/1),
      owner_timestamp: file.owner_timestamp,
      deleted_flag: false
    })
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp chunk_inode(file_id) do
    path = Default.unit() |> ChunkStore.file_dir(file_id) |> Path.join("0000000000")
    {:ok, %{inode: inode}} = File.stat(path)
    inode
  end

  defp b64(binary), do: Base.encode64(binary, padding: false)
end

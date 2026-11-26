defmodule ChatWeb.FileChunkWriteGateControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId
  alias Chat.Storage.Default

  setup do
    {owner, owner_card} = identity_with_card("Owner")
    {uploader, uploader_card} = identity_with_card("Uploader")

    %{owner: owner, owner_card: owner_card, uploader: uploader, uploader_card: uploader_card}
  end

  for mode <- [:guarded, :trust] do
    describe "PUT /electric/v1/file_chunk in #{mode} mode" do
      setup ctx do
        put_gate(unquote(mode), ctx.owner_card)
        :ok
      end

      test "refuses an uploader without a write vouch", ctx do
        {conn, file_id} = put_chunk(ctx.conn, ctx.uploader, ctx.uploader_card)

        assert conn.status == 403

        assert %{"error" => "not_in_trust_chain", "max_depth" => _} =
                 Jason.decode!(conn.resp_body)

        refute ChunkStore.exists?(Default.unit(), file_id, 0)
      end

      test "accepts an uploader vouched for file_chunk writes", ctx do
        vouch(
          ctx.owner,
          ctx.owner_card.user_hash,
          ctx.uploader_card.user_hash,
          "storage.write.file_chunk"
        )

        {conn, file_id} = put_chunk(ctx.conn, ctx.uploader, ctx.uploader_card)

        assert conn.status == 200
        assert ChunkStore.exists?(Default.unit(), file_id, 0)
      end

      test "accepts the owner", ctx do
        {conn, _file_id} = put_chunk(ctx.conn, ctx.owner, ctx.owner_card)

        assert conn.status == 200
      end
    end
  end

  defp put_chunk(conn, identity, card) do
    file_id = FileId.generate()
    raw_data = :crypto.strong_rand_bytes(100)
    data_hash = raw_data |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()
    timestamp = System.os_time(:millisecond)

    sign_b64 =
      %FileChunk{
        file_id: file_id,
        chunk_index: 0,
        data_hash: data_hash,
        size: byte_size(raw_data),
        uploader_hash: card.user_hash,
        owner_timestamp: timestamp
      }
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    conn =
      conn
      |> put_req_header("x-data-hash", data_hash)
      |> put_req_header("x-size", to_string(byte_size(raw_data)))
      |> put_req_header("x-uploader-hash", card.user_hash)
      |> put_req_header("x-owner-timestamp", to_string(timestamp))
      |> put_req_header("x-signature", Base.encode64(sign_b64, padding: false))
      |> put_req_header("content-type", "application/octet-stream")
      |> put("/electric/v1/file_chunk/#{file_id}/0", raw_data)

    {conn, file_id}
  end
end

defmodule ChatWeb.ElectricControllerFileTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UploadChunk
  alias Chat.Data.Types.FileId
  alias Chat.Data.User, as: UserData
  alias Chat.Repo

  setup %{conn: conn} do
    identity = UserData.generate_pq_identity("Alice")
    card = UserData.extract_pq_card(identity)
    insert_card(conn, card, identity.sign_skey)

    {:ok, identity: identity, card: card, user_hash: card.user_hash}
  end

  describe "file_chunk ingest" do
    test "insert returns txid", %{conn: conn, identity: identity, user_hash: user_hash} do
      {chunk, _data_b64} = build_signed_chunk(identity, user_hash, FileId.generate(), 0)
      payload = file_chunk_insert_payload(chunk)

      conn = post_ingest(conn, payload, identity.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
      assert is_integer(txid)
    end

    test "insert persists chunk and bookkeeping row", %{
      conn: conn,
      identity: identity,
      user_hash: user_hash
    } do
      file_id = FileId.generate()
      {chunk, _data_b64} = build_signed_chunk(identity, user_hash, file_id, 0)
      payload = file_chunk_insert_payload(chunk)

      conn = post_ingest(conn, payload, identity.sign_skey)
      assert conn.status == 200

      assert Repo.get_by(FileChunk, file_id: file_id, chunk_index: 0) != nil
      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) != nil
    end

    test "insert without PoP returns 401", %{conn: conn, identity: identity, user_hash: user_hash} do
      {chunk, _} = build_signed_chunk(identity, user_hash, FileId.generate(), 0)
      payload = file_chunk_insert_payload(chunk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(payload))

      assert conn.status == 401
    end
  end

  describe "file (manifest) ingest" do
    test "insert with all chunks present returns txid", %{
      conn: conn,
      identity: identity,
      user_hash: user_hash
    } do
      file_id = FileId.generate()

      {chunk, _} = build_signed_chunk(identity, user_hash, file_id, 0)
      chunk_conn = post_ingest(conn, file_chunk_insert_payload(chunk), identity.sign_skey)
      assert chunk_conn.status == 200

      file = build_signed_file(identity, user_hash, file_id, [chunk])
      file_conn = post_ingest(conn, file_insert_payload(file), identity.sign_skey)

      assert file_conn.status == 200, file_conn.resp_body
      assert %{"txid" => _} = Jason.decode!(file_conn.resp_body)
    end

    test "insert verifies chunks and cleans upload_chunks", %{
      conn: conn,
      identity: identity,
      user_hash: user_hash
    } do
      file_id = FileId.generate()

      {chunk, _} = build_signed_chunk(identity, user_hash, file_id, 0)
      assert post_ingest(conn, file_chunk_insert_payload(chunk), identity.sign_skey).status == 200

      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) != nil

      file = build_signed_file(identity, user_hash, file_id, [chunk])
      assert post_ingest(conn, file_insert_payload(file), identity.sign_skey).status == 200

      assert Repo.get(FileSchema, file_id) != nil
      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) == nil
    end

    test "insert without PoP returns 401", %{conn: conn, identity: identity, user_hash: user_hash} do
      file = build_signed_file(identity, user_hash, FileId.generate(), [])
      payload = file_insert_payload(file)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/electric/v1/ingest", Jason.encode!(payload))

      assert conn.status == 401
    end
  end

  # --- Payload builders ---

  defp file_chunk_insert_payload(chunk) do
    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "file_id" => chunk.file_id,
            "chunk_index" => chunk.chunk_index,
            "data_b64" => to_base64(chunk.data_b64),
            "size" => chunk.size,
            "uploader_hash" => chunk.uploader_hash,
            "owner_timestamp" => chunk.owner_timestamp,
            "sign_b64" => to_base64(chunk.sign_b64)
          },
          "syncMetadata" => %{"relation" => "file_chunks"}
        }
      ]
    }
  end

  defp file_insert_payload(file) do
    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "file_id" => file.file_id,
            "uploader_hash" => file.uploader_hash,
            "total_size" => file.total_size,
            "chunk_size" => file.chunk_size,
            "chunk_count" => file.chunk_count,
            "chunk_sign_hashes" => Enum.map(file.chunk_sign_hashes, &to_base64/1),
            "owner_timestamp" => file.owner_timestamp,
            "deleted_flag" => file.deleted_flag,
            "sign_b64" => to_base64(file.sign_b64)
          },
          "syncMetadata" => %{"relation" => "files"}
        }
      ]
    }
  end

  # --- Signed struct builders ---

  defp build_signed_chunk(identity, user_hash, file_id, index) do
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
    {%{chunk | sign_b64: sign_b64}, data_b64}
  end

  defp build_signed_file(identity, user_hash, file_id, chunks) do
    chunk_sign_hashes = Enum.map(chunks, &EnigmaPq.hash(&1.sign_b64))
    chunk_size = 4_194_304
    total_size = length(chunks) * chunk_size

    file = %FileSchema{
      file_id: file_id,
      uploader_hash: user_hash,
      total_size: total_size,
      chunk_size: chunk_size,
      chunk_count: length(chunks),
      chunk_sign_hashes: chunk_sign_hashes,
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    sign_b64 = file |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{file | sign_b64: sign_b64}
  end

  # --- Shared helpers ---

  defp insert_card(conn, card, sign_skey) do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => card.user_hash,
            "sign_pkey" => to_base64(card.sign_pkey),
            "contact_pkey" => to_base64(card.contact_pkey),
            "contact_cert" => to_base64(card.contact_cert),
            "crypt_pkey" => to_base64(card.crypt_pkey),
            "crypt_cert" => to_base64(card.crypt_cert),
            "name" => card.name,
            "deleted_flag" => card.deleted_flag,
            "owner_timestamp" => card.owner_timestamp,
            "sign_b64" => to_base64(card.sign_b64)
          },
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }

    result = post_ingest(conn, payload, sign_skey)
    assert result.status == 200, result.resp_body
    result
  end

  defp to_base64(bin), do: Base.encode64(bin, padding: false)

  defp post_ingest(conn, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    signature_b64 =
      challenge
      |> EnigmaPq.sign(sign_skey)
      |> Base.encode64(padding: false)

    payload =
      payload
      |> Map.put("auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end
end

defmodule ChatWeb.FileChunkControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UploadChunk
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId
  alias Chat.Data.User, as: UserData
  alias Chat.Db.Common
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  @drive_id :test_chunk_ctrl

  setup %{conn: conn} do
    identity = UserData.generate_pq_identity("Alice")
    card = UserData.extract_pq_card(identity)

    signed_card = sign_card(card, identity)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, signed_card)

    tmp_dir = System.tmp_dir!() |> Path.join("chunk_ctrl_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    prev_base = Common.get_chat_db_env(:files_base_dir)
    Common.put_chat_db_env(:files_base_dir, tmp_dir)

    {:ok, writer_pid} =
      ChunkWriter.start_link(drive_id: @drive_id, base_dir: tmp_dir)

    prev_drive = Application.get_env(:chat, :active_drive_id)
    Common.put_chat_db_env(:active_drive_id, @drive_id)

    on_exit(fn ->
      if Process.alive?(writer_pid), do: GenServer.stop(writer_pid)
      Common.put_chat_db_env(:files_base_dir, prev_base)
      if prev_drive, do: Common.put_chat_db_env(:active_drive_id, prev_drive)
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     identity: identity,
     card: card,
     user_hash: card.user_hash,
     conn: conn,
     tmp_dir: tmp_dir}
  end

  describe "GET /electric/v1/file_chunk/:file_id/:chunk_index (show)" do
    test "returns chunk data when chunk and file exist", %{
      conn: conn,
      identity: identity,
      user_hash: uh,
      tmp_dir: tmp_dir
    } do
      file_id = FileId.generate()
      raw_data = :crypto.strong_rand_bytes(100)
      chunk = insert_file_chunk(identity, uh, file_id, 0)

      :ok = ChunkStore.put(file_id, 0, raw_data, tmp_dir)

      conn = get(conn, "/electric/v1/file_chunk/#{file_id}/0")

      assert conn.status == 200
      assert conn.resp_body == raw_data
      assert get_resp_header(conn, "x-chunk-size") == [to_string(chunk.size)]
    end

    test "returns 404 when DB record missing", %{conn: conn} do
      conn = get(conn, "/electric/v1/file_chunk/#{FileId.generate()}/0")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "chunk not found"
    end

    test "returns 404 when filesystem data missing", %{
      conn: conn,
      identity: identity,
      user_hash: uh
    } do
      file_id = FileId.generate()
      _chunk = insert_file_chunk(identity, uh, file_id, 0)

      conn = get(conn, "/electric/v1/file_chunk/#{file_id}/0")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "chunk data not found"
    end

    test "returns 400 for non-numeric chunk_index", %{conn: conn} do
      conn = get(conn, "/electric/v1/file_chunk/#{FileId.generate()}/abc")
      assert conn.status == 400
    end
  end

  describe "PUT /electric/v1/file_chunk/:file_id/:chunk_index (create)" do
    test "accepts valid upload and persists chunk", %{
      conn: conn,
      identity: identity,
      user_hash: uh,
      tmp_dir: tmp_dir
    } do
      file_id = FileId.generate()
      raw_data = :crypto.strong_rand_bytes(100)
      headers = build_upload_headers(identity, uh, file_id, 0, raw_data)

      conn =
        conn
        |> put_upload_headers(headers)
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/electric/v1/file_chunk/#{file_id}/0", raw_data)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["status"] == "ok"

      assert Repo.get_by(FileChunk, file_id: file_id, chunk_index: 0) != nil
      assert Repo.get_by(UploadChunk, file_id: file_id, chunk_index: 0) != nil

      assert {:ok, ^raw_data} = ChunkStore.fetch(file_id, 0, tmp_dir)
    end

    test "returns 400 when headers missing", %{conn: conn} do
      file_id = FileId.generate()

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/electric/v1/file_chunk/#{file_id}/0", "data")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "missing required headers"
    end

    test "returns 401 for invalid signature", %{conn: conn, identity: identity, user_hash: uh} do
      file_id = FileId.generate()
      raw_data = :crypto.strong_rand_bytes(100)
      headers = build_upload_headers(identity, uh, file_id, 0, raw_data)

      bad_sig = Base.encode64(:crypto.strong_rand_bytes(64), padding: false)
      headers = %{headers | signature_b64: bad_sig}

      conn =
        conn
        |> put_upload_headers(headers)
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/electric/v1/file_chunk/#{file_id}/0", raw_data)

      assert conn.status == 401
    end

    test "returns 410 for deleted file", %{conn: conn, identity: identity, user_hash: uh} do
      file_id = FileId.generate()
      raw_data = :crypto.strong_rand_bytes(100)

      insert_deleted_file(identity, uh, file_id)

      headers = build_upload_headers(identity, uh, file_id, 0, raw_data)

      conn =
        conn
        |> put_upload_headers(headers)
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/electric/v1/file_chunk/#{file_id}/0", raw_data)

      assert conn.status == 410
    end

    test "returns 422 for hash mismatch", %{conn: conn, identity: identity, user_hash: uh} do
      file_id = FileId.generate()
      raw_data = :crypto.strong_rand_bytes(100)
      wrong_data = :crypto.strong_rand_bytes(100)

      headers = build_upload_headers(identity, uh, file_id, 0, raw_data)

      conn =
        conn
        |> put_upload_headers(headers)
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/electric/v1/file_chunk/#{file_id}/0", wrong_data)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "body hash mismatch"
    end

    test "OPTIONS returns 204", %{conn: conn} do
      conn = options(conn, "/electric/v1/file_chunk/#{FileId.generate()}/0")
      assert conn.status == 204
    end
  end

  # Helpers

  defp insert_file_chunk(identity, user_hash, file_id, index) do
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
    signed = %{chunk | sign_b64: sign_b64}

    changeset = FileChunk.create_changeset(%FileChunk{}, Map.from_struct(signed) |> Map.drop([:__meta__]))
    {:ok, _} = Repo.insert(changeset)
    signed
  end

  defp insert_deleted_file(identity, user_hash, file_id) do
    alias Chat.Data.Schemas.File, as: FileSchema

    file = %FileSchema{
      file_id: file_id,
      uploader_hash: user_hash,
      total_size: 100,
      chunk_size: 100,
      chunk_count: 1,
      chunk_sign_hashes: [],
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: true
    }

    sign_b64 = file |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:file, :insert, %{file | sign_b64: sign_b64})
  end

  defp build_upload_headers(identity, user_hash, file_id, index, raw_data) do
    data_hash = raw_data |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()
    timestamp = System.os_time(:millisecond)

    chunk = %FileChunk{
      file_id: file_id,
      chunk_index: index,
      data_hash: data_hash,
      size: byte_size(raw_data),
      uploader_hash: user_hash,
      owner_timestamp: timestamp
    }

    sign_b64 = chunk |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)

    %{
      data_hash: data_hash,
      size: to_string(byte_size(raw_data)),
      uploader_hash: user_hash,
      owner_timestamp: to_string(timestamp),
      signature_b64: Base.encode64(sign_b64, padding: false)
    }
  end

  defp put_upload_headers(conn, headers) do
    conn
    |> put_req_header("x-data-hash", headers.data_hash)
    |> put_req_header("x-size", headers.size)
    |> put_req_header("x-uploader-hash", headers.uploader_hash)
    |> put_req_header("x-owner-timestamp", headers.owner_timestamp)
    |> put_req_header("x-signature", headers.signature_b64)
  end

  defp sign_card(card, identity) do
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end
end

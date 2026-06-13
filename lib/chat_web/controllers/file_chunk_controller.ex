defmodule ChatWeb.FileChunkController do
  use ChatWeb, :controller

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.TimeKeeper
  alias EnigmaPq

  @max_chunk_body 5_242_880
  @min_free_bytes 50_000_000

  def show(conn, %{"file_id" => file_id, "chunk_index" => chunk_index_str}) do
    with {chunk_index, ""} <- Integer.parse(chunk_index_str),
         %{} = chunk <- FileData.get_file_chunk(file_id, chunk_index),
         {:ok, data} <- ChunkStore.fetch(file_id, chunk_index) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("x-chunk-size", to_string(chunk.size))
      |> send_resp(200, data)
    else
      nil -> send_resp(conn, 404, Jason.encode!(%{error: "chunk not found"}))
      {:error, :enoent} -> send_resp(conn, 404, Jason.encode!(%{error: "chunk data not found"}))
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid chunk_index"}))
    end
  end

  def create(conn, %{"file_id" => file_id, "chunk_index" => chunk_index_str}) do
    with {chunk_index, ""} <- Integer.parse(chunk_index_str),
         {:ok, headers} <- parse_chunk_headers(conn),
         :ok <- check_file_not_deleted(file_id, headers.uploader_hash),
         chunk = build_chunk(file_id, chunk_index, headers),
         :ok <- Integrity.verify_signature(chunk),
         :ok <- check_free_space(headers.size),
         {:ok, body, conn} <- read_chunk_body(conn),
         :ok <- verify_body_hash(body, headers.data_hash),
         :ok <- verify_body_size(body, headers.size),
         :ok <- ChunkStore.put(file_id, chunk_index, body),
         {:ok, _} <- persist_chunk(chunk) do
      json(conn, %{status: "ok"})
    else
      {:error, :invalid_signature} ->
        send_resp(conn, 401, Jason.encode!(%{error: "invalid signature"}))

      {:error, :file_deleted} ->
        send_resp(conn, 410, Jason.encode!(%{error: "file deleted"}))

      {:error, :uploader_mismatch} ->
        send_resp(conn, 403, Jason.encode!(%{error: "uploader mismatch"}))

      {:error, :hash_mismatch} ->
        send_resp(conn, 422, Jason.encode!(%{error: "body hash mismatch"}))

      {:error, :size_mismatch} ->
        send_resp(conn, 422, Jason.encode!(%{error: "body size mismatch"}))

      {:error, :insufficient_space} ->
        send_resp(conn, 413, Jason.encode!(%{error: "insufficient disk space"}))

      {:error, :body_too_large} ->
        send_resp(conn, 413, Jason.encode!(%{error: "chunk too large"}))

      {:error, :missing_headers} ->
        send_resp(conn, 400, Jason.encode!(%{error: "missing required headers"}))

      _ ->
        send_resp(conn, 400, Jason.encode!(%{error: "bad request"}))
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")

  defp parse_chunk_headers(conn) do
    with [data_hash] <- get_req_header(conn, "x-data-hash"),
         [size_str] <- get_req_header(conn, "x-size"),
         [uploader_hash] <- get_req_header(conn, "x-uploader-hash"),
         [timestamp_str] <- get_req_header(conn, "x-owner-timestamp"),
         [signature_b64] <- get_req_header(conn, "x-signature"),
         {size, ""} <- Integer.parse(size_str),
         {owner_timestamp, ""} <- Integer.parse(timestamp_str),
         {:ok, sign_b64} <- Base.decode64(signature_b64, padding: false) do
      {:ok,
       %{
         data_hash: data_hash,
         size: size,
         uploader_hash: uploader_hash,
         owner_timestamp: owner_timestamp,
         sign_b64: sign_b64
       }}
    else
      _ -> {:error, :missing_headers}
    end
  end

  defp build_chunk(file_id, chunk_index, headers) do
    %FileChunk{
      file_id: file_id,
      chunk_index: chunk_index,
      data_hash: headers.data_hash,
      size: headers.size,
      uploader_hash: headers.uploader_hash,
      owner_timestamp: headers.owner_timestamp,
      sign_b64: headers.sign_b64
    }
  end

  defp check_free_space(chunk_size) do
    case ChunkStore.available_space() do
      {:ok, free} when free > chunk_size + @min_free_bytes -> :ok
      {:ok, _} -> {:error, :insufficient_space}
      {:error, _} -> :ok
    end
  end

  defp check_file_not_deleted(file_id, uploader_hash) do
    case FileData.get_file(file_id) do
      nil -> :ok
      %{deleted_flag: true} -> {:error, :file_deleted}
      %{uploader_hash: ^uploader_hash} -> :ok
      _ -> {:error, :uploader_mismatch}
    end
  end

  defp read_chunk_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_chunk_body) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, _reason} -> {:error, :body_too_large}
    end
  end

  defp verify_body_hash(body, expected_data_hash) do
    actual = body |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()

    if actual == expected_data_hash,
      do: :ok,
      else: {:error, :hash_mismatch}
  end

  defp verify_body_size(body, expected_size) do
    if byte_size(body) == expected_size,
      do: :ok,
      else: {:error, :size_mismatch}
  end

  defp persist_chunk(chunk) do
    chunk_sign_hash = EnigmaPq.hash(chunk.sign_b64)
    attrs = Map.from_struct(chunk) |> Map.drop([:__meta__])

    changeset = FileChunk.create_changeset(%FileChunk{}, attrs)

    with {:ok, _} <- FileData.insert_file_chunk(changeset) do
      FileData.insert_upload_chunk(%{
        file_id: chunk.file_id,
        chunk_index: chunk.chunk_index,
        chunk_sign_hash: chunk_sign_hash,
        uploader_hash: chunk.uploader_hash,
        size: chunk.size,
        updated_at: TimeKeeper.now_unix()
      })
    end
  end
end

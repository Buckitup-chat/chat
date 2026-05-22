defmodule ChatWeb.FileChunkController do
  use ChatWeb, :controller

  alias Chat.Data.File, as: FileData

  def show(conn, %{"file_id" => file_id, "chunk_index" => chunk_index_str}) do
    with {chunk_index, ""} <- Integer.parse(chunk_index_str),
         %{} = chunk <- FileData.get_file_chunk(file_id, chunk_index) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("x-chunk-size", to_string(chunk.size))
      |> send_resp(200, chunk.data_b64)
    else
      nil -> send_resp(conn, 404, Jason.encode!(%{error: "chunk not found"}))
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid chunk_index"}))
    end
  end
end

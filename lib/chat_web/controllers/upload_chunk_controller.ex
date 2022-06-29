defmodule ChatWeb.UploadChunkController do
  @moduledoc "Serve files"
  use ChatWeb, :controller
  require Logger

  alias Chat.ChunkedFiles

  def put(conn, params) do
    with %{"key" => key} <- params,
         {:ok, chunk, conn} <- read_out_chunk(conn),
         [range] <- get_req_header(conn, "content-range"),
         {range_start, range_end, _size} <- parse_range(range) do
      ChunkedFiles.save_upload_chunk(key, {range_start, range_end}, chunk)

      conn
      |> send_resp(200, "")
    else
      e ->
        Logger.error(inspect(e))
        raise "404"
    end
  end

  defp read_out_chunk(conn, acc \\ [""]) do
    case read_body(conn) do
      {:ok, data, conn} ->
        {:ok, IO.iodata_to_binary([acc, data]), conn}

      {:more, chunk, conn} ->
        read_out_chunk(conn, [acc, chunk])
    end
  end

  defp parse_range("bytes " <> str) do
    [range, size] = String.split(str, "/", parts: 2)

    [range_start, range_end] =
      range
      |> String.split("-", parts: 2)
      |> Enum.map(&String.to_integer/1)

    {range_start, range_end, size |> String.to_integer()}
  end
end

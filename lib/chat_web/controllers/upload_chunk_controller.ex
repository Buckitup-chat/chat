defmodule ChatWeb.UploadChunkController do
  @moduledoc "Serve files"
  use ChatWeb, :controller
  require Logger

  alias Chat.ChunkedFiles

  def put(conn, params) do
    with %{"key" => key} <- params,
         {:ok, chunk, conn} <- read_out_chunk(conn),
         [range] <- get_req_header(conn, "content-range"),
         {range_start, range_end, _size} <- parse_range(range),
         :ok <- save_chunk_till({key, {range_start, range_end}, chunk}, time_mark() + 10) do
      conn
      |> send_resp(200, "")
    else
      e ->
        Logger.error("[upload] error processing chunk " <> inspect(e))

        conn
        |> send_resp(503, "Busy")
    end
  end

  defp save_chunk_till({key, range, chunk} = data, till) do
    cond do
      :ok == ChunkedFiles.save_upload_chunk(key, range, chunk) -> :ok
      time_mark() > till -> :failed
      true -> save_chunk_till(data, till)
    end
  end

  defp time_mark, do: System.monotonic_time(:second)

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

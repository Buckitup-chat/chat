defmodule ChatWeb.FileController do
  @moduledoc "Serve files"
  use ChatWeb, :controller

  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Content.Files

  # can do part downloads with https://elixirforum.com/t/question-regarding-send-download-send-file-from-binary-in-memory/32507/4

  def image(conn, %{"download" => _} = params) do
    render_file(conn, params, disposition: true, content_type: "octet/stream")
  end

  def image(conn, params) do
    render_file(conn, params, content_type: true)
  end

  def file(conn, params) do
    render_file(conn, params, disposition: true, content_type: true)
  end

  def backup(conn, params) do
    with %{"key" => key} <- params,
         {name, data} <- Broker.get(key) do
      conn
      |> put_resp_header("content-disposition", "attachment; filename=\"#{name}\"")
      |> put_resp_content_type("application/octet-stream")
      |> send_resp(200, data)
    else
      _ -> raise "404"
    end
  rescue
    _ ->
      conn
      |> send_resp(404, "")
  end

  defp render_file(conn, params, opts) do
    with %{"id" => id, "a" => secret} <- params,
         [chunk_key, chunk_secret_raw, _, type, name | _] <-
           Files.get(id, secret |> Base.url_decode64!()),
         chunk_secret <- chunk_secret_raw |> Base.decode64!(),
         true <- type |> String.contains?("/") do
      size = ChunkedFiles.size(chunk_key)

      range = get_req_header(conn, "range")
      proto = get_http_protocol(conn)

      case {proto, range} do
        #        {:"HTTP/22", _} ->
        #          "here" |> IO.inspect()
        #
        #          conn =
        #            conn
        #            |> set_disposition(name, opts[:disposition])
        #            |> put_resp_header("content-length", "#{size}")
        #            |> set_content_type(type, opts[:content_type])
        #            |> send_chunked(200)
        #
        #          size
        #          |> ChunkedFiles.file_chunk_ranges()
        #          |> Enum.reduce_while(conn, fn range, conn ->
        #            chunk = ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret}, range) |> elem(1)
        #
        #            case Plug.Conn.chunk(conn, chunk) do
        #              {:ok, conn} ->
        #                {:cont, conn}
        #
        #              {:error, :closed} ->
        #                {:halt, conn}
        #            end
        #          end)

        {_, []} ->
          conn =
            conn
            |> set_disposition(name, opts[:disposition])
            |> put_resp_header("content-length", "#{size}")
            |> set_content_type(type, opts[:content_type])
            |> send_chunked(200)

          size
          |> ChunkedFiles.file_chunk_ranges()
          |> Enum.reduce_while(conn, fn range, conn ->
            chunk = ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret}, range) |> elem(1)

            case Plug.Conn.chunk(conn, chunk) do
              {:ok, conn} ->
                {:cont, conn}

              {:error, :closed} ->
                {:halt, conn}
            end
          end)

        {_, range} ->
          {{first, last}, data} =
            case parse_range(range) do
              nil ->
                ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret})

              {from, to} when is_integer(from) and is_integer(to) and from >= 0 and to >= from ->
                ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret}, {from, to})

              {from, nil} when is_integer(from) ->
                ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret}, {from, nil})
            end

          conn
          |> set_disposition(name, opts[:disposition])
          |> set_content_type(type, opts[:content_type])
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
          |> put_resp_header("content-length", "#{size}")
          |> resp(:partial_content, data)
          |> send_resp()
      end
    else
      _ ->
        raise "404"
    end
  rescue
    _ ->
      conn
      |> send_resp(404, "")
  end

  defp parse_range(["bytes=" <> range | _]) do
    range
    |> String.split("-")
    |> case do
      [""] -> nil
      ["", ""] -> nil
      [from, ""] -> {from |> String.to_integer(), nil}
      [from, "*"] -> {from |> String.to_integer(), nil}
      [from, to] -> {from |> String.to_integer(), to |> String.to_integer()}
    end
  end

  defp parse_range(_), do: nil

  defp set_disposition(conn, name, true),
    do: put_resp_header(conn, "content-disposition", "attachment; filename=\"#{name}\"")

  defp set_disposition(conn, _, _), do: conn

  defp set_content_type(conn, file_type, content_type) do
    case content_type do
      nil -> conn
      true -> put_resp_content_type(conn, file_type)
      override_type -> put_resp_content_type(conn, override_type)
    end
  end
end

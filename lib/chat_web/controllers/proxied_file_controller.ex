defmodule ChatWeb.ProxiedFileController do
  @moduledoc "Serve files"
  use ChatWeb, :controller

  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret

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

  defp render_file(conn, params, opts) do
    with %{"id" => id, "a" => secret, "server" => server} <- params,
         [chunk_key, chunk_secret_raw, size_str, type, name | _] <-
           file_info(server, id |> Base.decode16!(case: :lower), secret |> Base.url_decode64!()),
         chunk_secret <- chunk_secret_raw |> Base.decode64!(),
         true <- type |> String.contains?("/") do
      size = String.to_integer(size_str)
      range = get_req_header(conn, "range")
      proto = get_http_protocol(conn)

      case {proto, range, type} do
        {_, [], _} ->
          conn
          |> set_disposition(name, opts[:disposition])
          |> put_resp_header("content-length", "#{size}")
          |> set_content_type(type, opts[:content_type])
          |> send_chunked(200)
          |> passthrou_whole_file(size, chunk_key, chunk_secret, server)

        {_, ["bytes=0-" <> _] = range, "video/" <> _} ->
          {first, last, data} = handle_chunking(range, size, chunk_key, chunk_secret, server)

          conn
          |> set_disposition(name, opts[:disposition])
          |> set_content_type(type, opts[:content_type])
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
          |> put_resp_header("content-length", "#{size}")
          |> resp(:partial_content, data)
          |> send_resp()

        {_, _range, "video/" <> _} ->
          conn
          |> set_disposition(name, opts[:disposition])
          |> put_resp_header("content-length", "#{size}")
          |> set_content_type(type, opts[:content_type])
          |> send_chunked(200)
          |> passthrou_whole_file(size, chunk_key, chunk_secret, server)

        {_, range, type} ->
          {first, last, data} = handle_chunking(range, size, chunk_key, chunk_secret, server)

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

  defp handle_chunking(range, size, chunk_key, chunk_secret, server) do
    {first, last} =
      case parse_range(range) do
        nil ->
          {0, size - 1}

        {from, to} when is_integer(from) and is_integer(to) and from >= 0 and to >= from ->
          {from, to}

        {from, nil} when is_integer(from) ->
          {from, size - 1}
      end

    # data = ChunkedFiles.chunk_with_byterange({chunk_key, chunk_secret}, {first, last}) |> elem(1)
    data = chunk_with_byterange({chunk_key, chunk_secret}, {first, last}, server) |> elem(1)
    {first, last, data}
  end

  defp passthrou_whole_file(conn, size, chunk_key, chunk_secret, server) do
    size
    |> ChunkedFiles.file_chunk_ranges()
    |> Enum.reduce_while(conn, fn range, conn ->
      chunk = chunk_with_byterange({chunk_key, chunk_secret}, range, server) |> elem(1)

      case Plug.Conn.chunk(conn, chunk) do
        {:ok, conn} ->
          {:cont, conn}

        {:error, :closed} ->
          {:halt, conn}
      end
    end)
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

  @chunk_size Application.compile_env(:chat, :file_chunk_size)
  defp chunk_with_byterange({key, initial_secret}, {first, last}, server) do
    chunk_n = div(first, @chunk_size)
    chunk_start = chunk_n * @chunk_size
    start_bypass = first - chunk_start

    secret = get_secret_from_multisecret(key, chunk_start, initial_secret, server)
    {encrypt_blob, chunk_end} = read_file_chunk(chunk_start, key, server)

    range_length = min(last, chunk_end) - first + 1

    data =
      encrypt_blob
      |> Enigma.decipher(secret)
      |> :binary.part(start_bypass, range_length)

    {{first, first + range_length - 1}, data}
  end

  defp get_secret_from_multisecret(key, chunk_start, initial_secret, server) do
    ChunkedFilesMultisecret.get_secret(key, chunk_start, initial_secret, fn key ->
      Proxy.get_file_secrets(server, key)
    end)
  end

  defp file_info(server, key, secret) do
    Proxy.get_file_info(server, key)
    |> Enum.map(&Enigma.decipher(&1, secret))
  end

  defp read_file_chunk(chunk_start, key, server) do
    Proxy.read_file_chunk(server, key, chunk_start)
  end
end

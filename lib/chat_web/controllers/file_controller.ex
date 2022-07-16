defmodule ChatWeb.FileController do
  @moduledoc "Serve files"
  use ChatWeb, :controller

  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Files

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
         [chunk_key, chunk_secret, _, type, name | _] <-
           Files.get(id, secret |> Base.url_decode64!()),
         true <- type |> String.contains?("/") do
      data = ChunkedFiles.read({chunk_key, chunk_secret |> Base.decode64!()})

      conn
      |> set_disposition(name, opts[:disposition])
      |> set_content_type(type, opts[:content_type])
      |> send_resp(200, data)
    else
      _ -> raise "404"
    end
  rescue
    _ ->
      conn
      |> send_resp(404, "")
  end

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

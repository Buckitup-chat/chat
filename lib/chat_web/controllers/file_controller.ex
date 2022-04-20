defmodule ChatWeb.FileController do
  @moduledoc "Serve files"
  use ChatWeb, :controller

  alias Chat.Broker
  alias Chat.Images

  # can do part downloads with https://elixirforum.com/t/question-regarding-send-download-send-file-from-binary-in-memory/32507/4

  def image(conn, params) do
    with %{"id" => id, "a" => secret} <- params,
         {data, type} <- Images.get(id, secret |> Base.url_decode64!()),
         true <- type |> String.contains?("/") do
      conn
      |> put_resp_content_type(type)
      |> send_resp(200, data)
    else
      _ -> raise "404"
    end
  rescue
    _ ->
      conn
      |> send_resp(404, "")
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
end

defmodule ChatWeb.ReviewTokenController do
  @moduledoc "Handles review write token routes: GET /r/:nonce, POST /r/api/token/create, POST /r/api/token/bind."

  use ChatWeb, :controller

  alias Chat.Data.ReviewWriteToken
  alias Chat.ReviewBot.TokenBinder
  alias Chat.ReviewBot.TokenCreator
  alias ChatWeb.Utils.IngestPop

  def create(conn, params) do
    bot_hash = params["bot_hash"]
    origin_order_hash = params["origin_order_hash"]

    case TokenCreator.create(bot_hash, origin_order_hash) do
      {:ok, nonce} ->
        url = "#{ChatWeb.Endpoint.url()}/r/#{nonce}"
        json(conn, %{nonce: nonce, url: url})

      {:error, :bot_not_running} ->
        conn |> put_status(:not_found) |> json(%{error: "Bot not running"})

      {:error, :no_live_vouch} ->
        conn |> put_status(:forbidden) |> json(%{error: "No live vouch for this bot"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def bind(conn, %{"nonce" => nonce, "user_hash" => user_hash} = params) do
    with {:ok, pop_context} <- IngestPop.context(params),
         {:ok, bound_nonce} <- TokenBinder.bind(nonce, user_hash, pop_context) do
      url = "#{ChatWeb.Endpoint.url()}/r/#{bound_nonce}"
      json(conn, %{nonce: bound_nonce, url: url})
    else
      {:error, {:unauthorized, msg}} ->
        conn |> put_status(:unauthorized) |> json(%{error: msg})

      {:error, :token_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Token not found"})

      {:error, :token_deleted} ->
        conn |> put_status(:gone) |> json(%{error: "Token has been deleted"})

      {:error, :reviewer_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Reviewer identity not found"})

      {:error, :invalid_pop} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid proof of possession"})

      {:error, :bot_not_running} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "Review bot not running"})

      {:error, :no_bot_origin_vouch} ->
        conn |> put_status(:forbidden) |> json(%{error: "Bot lacks origin vouch"})

      {:error, :no_bot_device_vouch} ->
        conn |> put_status(:forbidden) |> json(%{error: "Bot lacks device vouch"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"nonce" => nonce}) do
    case ReviewWriteToken.get_review_write_token(nonce) do
      nil -> render_expired(conn)
      %{deleted_flag: true} -> render_expired(conn)
      _token -> serve_app(conn)
    end
  end

  defp render_expired(conn) do
    conn
    |> put_status(:gone)
    |> put_resp_content_type("text/html")
    |> send_resp(410, expired_html())
  end

  defp serve_app(conn) do
    path = Path.join(:code.priv_dir(:chat), "static/app/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
  end

  defp expired_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Link Expired</title>
      <style>
        body { font-family: system-ui, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #1a1a1a; color: #e0e0e0; }
        .container { text-align: center; padding: 2rem; }
        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
        p { color: #999; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>This link has expired</h1>
        <p>The review token is no longer valid.</p>
      </div>
    </body>
    </html>
    """
  end
end

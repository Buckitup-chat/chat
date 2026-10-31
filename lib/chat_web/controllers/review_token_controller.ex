defmodule ChatWeb.ReviewTokenController do
  @moduledoc "Handles review write token routes: GET /r/:nonce, POST /r/api/token/create, POST /r/api/token/bind."

  use ChatWeb, :controller

  alias Chat.Data.ReviewWriteToken
  alias Chat.ReviewBot.TokenBinder
  alias Chat.ReviewBot.TokenCreator
  alias Chat.ReviewBot.Worker
  alias ChatWeb.Utils.IngestPop

  def create(conn, params) do
    bot_hash = params["bot_hash"]
    origin_order_hash = params["origin_order_hash"]

    with {:ok, bearer} <- extract_bearer(conn),
         {:ok, origin_hash} <- fetch_bot_origin(bot_hash),
         :ok <- check_rate_limit(origin_hash),
         :ok <- Worker.verify_auth(bot_hash, bearer),
         {:ok, nonce} <- TokenCreator.create(bot_hash, origin_order_hash) do
      url = "#{ChatWeb.Endpoint.url()}/r/#{nonce}"
      json(conn, %{nonce: nonce, url: url})
    else
      {:error, :missing_auth_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Missing Authorization header"})

      {:error, :invalid_auth_token} ->
        conn |> put_status(:forbidden) |> json(%{error: "Invalid auth token"})

      {:error, :no_auth_token_configured} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "No auth token configured for this origin"})

      {:error, :bot_not_running} ->
        conn |> put_status(:not_found) |> json(%{error: "Bot not running"})

      {:error, :no_live_vouch} ->
        conn |> put_status(:forbidden) |> json(%{error: "No live vouch for this bot"})

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many requests"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_auth_token}
    end
  end

  defp fetch_bot_origin(bot_hash) do
    case Worker.running?(bot_hash) do
      true -> {:ok, Worker.info(bot_hash).origin_hash}
      false -> {:error, :bot_not_running}
    end
  end

  defp check_rate_limit(origin_hash) do
    case ChatWeb.RateLimiter.check({:token_create, origin_hash}) do
      :ok -> :ok
      {:error, retry_after} -> {:error, {:rate_limited, retry_after}}
    end
  end

  @bind_errors %{
    token_not_found: {:not_found, "Token not found"},
    token_deleted: {:gone, "Token has been deleted"},
    reviewer_not_found: {:not_found, "Reviewer identity not found"},
    invalid_pop: {:unauthorized, "Invalid proof of possession"},
    bot_not_running: {:service_unavailable, "Review bot not running"},
    no_bot_origin_vouch: {:forbidden, "Bot lacks origin vouch"},
    no_bot_device_vouch: {:forbidden, "Bot lacks device vouch"}
  }

  def bind(conn, %{"nonce" => nonce, "user_hash" => user_hash} = params) do
    with {:ok, pop_context} <- IngestPop.context(params),
         {:ok, bound_nonce} <- TokenBinder.bind(nonce, user_hash, pop_context) do
      url = "#{ChatWeb.Endpoint.url()}/r/#{bound_nonce}"
      json(conn, %{nonce: bound_nonce, url: url})
    else
      {:error, {:unauthorized, msg}} ->
        conn |> put_status(:unauthorized) |> json(%{error: msg})

      {:error, reason} ->
        {status, msg} = Map.get(@bind_errors, reason, {:unprocessable_entity, inspect(reason)})
        conn |> put_status(status) |> json(%{error: msg})
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

defmodule ChatWeb.ReviewTokenController do
  @moduledoc "Handles GET /r/:nonce — public entry point for review write tokens."

  use ChatWeb, :controller

  alias Chat.Data.ReviewWriteToken

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

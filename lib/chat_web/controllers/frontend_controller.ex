defmodule ChatWeb.FrontendController do
  use ChatWeb, :controller

  @doc """
  Renders the frontend/index.html file for all routes.
  """
  def index(conn, _params) do
    serve_spa(conn, "frontend")
  end

  def app(conn, _params) do
    serve_spa(conn, "app")
  end

  defp serve_spa(conn, dir) do
    path = Path.join(:code.priv_dir(:chat), "static/#{dir}/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
  end
end

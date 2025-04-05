defmodule ChatWeb.FrontendController do
  use ChatWeb, :controller

  @doc """
  Renders the frontend/index.html file for all routes.
  """
  def index(conn, _params) do
    render_frontend(conn)
  end
  # Private helper function to render the frontend/index.html file
  defp render_frontend(conn) do
    frontend_path = Path.join(:code.priv_dir(:chat), "static/frontend/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, frontend_path)
  end
end

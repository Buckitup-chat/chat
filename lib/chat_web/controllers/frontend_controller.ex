defmodule ChatWeb.FrontendController do
  use ChatWeb, :controller

  def app(conn, _params) do
    path = Path.join(:code.priv_dir(:chat), "static/app/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
  end
end

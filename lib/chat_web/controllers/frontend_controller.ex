defmodule ChatWeb.FrontendController do
  use ChatWeb, :controller

  def app(conn, _params) do
    path = Path.join(:code.priv_dir(:chat), "static/app/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
  end

  def redirect_to_app(conn, params) do
    suffix = params["path"] |> List.wrap() |> Enum.join("/")
    target = "/app/" <> suffix

    target =
      case conn.query_string do
        "" -> target
        qs -> "#{target}?#{qs}"
      end

    conn
    |> put_resp_header("location", target)
    |> send_resp(302, "")
  end
end

defmodule ChatWeb.ProxyApiController do
  use ChatWeb, :controller

  def select(conn, params) do
    with %{"args" => encoded_args} <- params,
         args <- Base.url_decode64!(encoded_args, padding: false),
         data <- Proxy.Api.select_data(args) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_resp(200, data)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, "Not found")
    end
  catch
    _, _ ->
      conn |> send_resp(404, "Not found")
  end

  def confirmation_token(conn, _params) do
    data = Proxy.Api.confirmation_token()

    conn
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, data)
  end

  def register_user(conn, _params) do
    {:ok, body, _conn} = conn |> read_body()
    data = Proxy.Api.register_user(body)

    conn
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, data)
  catch
    _, _ ->
      conn |> send_resp(404, "Not found")
  end
end

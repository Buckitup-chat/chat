defmodule ChatWeb.ProxyApiController do
  use ChatWeb, :controller

  def select(conn, params) do
    fn ->
      Proxy.Api.select_data(params |> decode_args())
    end
    |> run_and_respond(conn)
  end

  def key_value(conn, params) do
    fn ->
      Proxy.Api.key_value_data(params |> decode_args())
    end
    |> run_and_respond(conn)
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

  def create_dialog(conn, _params) do
    {:ok, body, _conn} = conn |> read_body()
    data = Proxy.Api.create_dialog(body)

    conn
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, data)
  catch
    _, _ ->
      conn |> send_resp(404, "Not found")
  end

  # Helpers
  ##################
  defp decode_args(params) do
    %{"args" => encoded_args} = params
    Base.url_decode64!(encoded_args, padding: false)
  end

  defp run_and_respond(action, conn) do
    data = action.()

    conn
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, data)
  catch
    _, _ ->
      conn |> send_resp(404, "Not found")
  end
end

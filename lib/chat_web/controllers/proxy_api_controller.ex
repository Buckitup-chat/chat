defmodule ChatWeb.ProxyApiController do
  use ChatWeb, :controller

  def select(conn, params) do
    run_and_respond(conn, params, fn args ->
      Proxy.Api.select_data(args)
    end)
  end

  def key_value(conn, params) do
    run_and_respond(conn, params, fn args ->
      Proxy.Api.key_value_data(args)
    end)
  end

  def confirmation_token(conn, params) do
    run_and_respond(conn, params, fn _ ->
      Proxy.Api.confirmation_token()
    end)
  end

  def register_user(conn, params) do
    run_and_respond(conn, params, fn body ->
      Proxy.Api.register_user(body)
    end)
  end

  def create_dialog(conn, params) do
    run_and_respond(conn, params, fn body ->
      Proxy.Api.create_dialog(body)
    end)
  end

  def save_parcel(conn, params) do
    run_and_respond(conn, params, fn body ->
      Proxy.Api.save_parcel(body)
    end)
  end

  # Helpers
  ##################
  defp decode_args(params) do
    %{"args" => encoded_args} = params
    Base.url_decode64!(encoded_args, padding: false)
  end

  defp run_and_respond(conn, params, action) do
    data =
      case conn.method do
        "POST" ->
          {:ok, body, _conn} = conn |> read_body()
          body

        _ ->
          params |> decode_args()
      end
      |> then(action)

    conn
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, data)
  catch
    _, _ ->
      conn |> send_resp(404, "Not found")
  end
end

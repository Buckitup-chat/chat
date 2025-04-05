defmodule ChatWeb.ProxyApiController do
  use ChatWeb, :controller

  alias Proxy.Api

  # Endpoint generation
  %{
    select: &Api.select_data/1,
    key_value: &Api.key_value_data/1,
    confirmation_token: &Api.confirmation_token/1,
    register_user: &Api.register_user/1,
    create_dialog: &Api.create_dialog/1,
    save_parcel: &Api.save_parcel/1,
    bulk_get: &Api.bulk_get_data/1,
    request_room_access: &Api.request_room_access/1,
    approve_room_request: &Api.approve_room_request/1,
    clean_room_request: &Api.clean_room_request/1
  }
  |> Enum.each(fn {name, action} ->
    def unquote(name)(conn, params) do
      run_and_respond(conn, params, unquote(action))
    end
  end)

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

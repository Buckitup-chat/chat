defmodule ChatWeb.UnusedTrafficControllerTest do
  use ChatWeb.ConnCase, async: true

  test "not_available returns 503 Service Unavailable", %{conn: conn} do
    conn =
      conn
      |> bypass_through(ChatWeb.Router, :browser)
      |> get("/")
      |> Phoenix.Controller.put_view(ChatWeb.ErrorView)
      |> ChatWeb.UnusedTrafficController.not_available(%{})

    assert conn.status == 503
    assert conn.resp_body == "Try later"
    assert get_resp_header(conn, "retry-after") == ["600"]
  end
end

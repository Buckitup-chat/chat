defmodule ChatWeb.PageControllerTest do
  use ChatWeb.ConnCase

  @tag :skip
  test "GET /index", %{conn: conn} do
    conn = get(conn, "/index")
    assert html_response(conn, 200) =~ "Welcome to Phoenix!"
  end
end

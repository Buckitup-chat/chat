defmodule ChatWeb.PageControllerTest do
  use ChatWeb.ConnCase, async: true

  describe "GET / and unknown paths (FrontendController.redirect_to_app)" do
    test "root redirects to the SPA", %{conn: conn} do
      conn = get(conn, "/")

      assert redirected_to(conn, 302) == "/app/"
    end

    test "unknown path is carried over with its query string", %{conn: conn} do
      conn = get(conn, "/some/deep/link?invite=abc&x=1")

      assert redirected_to(conn, 302) == "/app/some/deep/link?invite=abc&x=1"
    end
  end
end

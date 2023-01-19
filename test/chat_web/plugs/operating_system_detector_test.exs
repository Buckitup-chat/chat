defmodule ChatWeb.Plugs.DetectOperatingSystemTest do
  use ChatWeb.ConnCase, async: true

  describe "call/2" do
    setup %{conn: conn} do
      %{conn: Map.put(conn, :host, "buckitup.app")}
    end

    test "detects Android device", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (Linux; Android 4.0.4; Galaxy Nexus Build/IMM76B) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.133 Mobile Safari/535.19"
        )
        |> get("/")

      assert get_session(conn, :operating_system) == "Android"
    end

    test "detects other device", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"
        )
        |> get("/")

      assert get_session(conn, :operating_system) == "Mac OS X"
    end

    test "parses reduced User-Agent string properly", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "user-agent",
          ~S(Sec-CH-UA: "Chrome"; v="93" Sec-CH-UA-Mobile: ?1 Sec-CH-UA-Platform: "Android" Sec-CH-UA-Model: "Pixel 2")
        )
        |> get("/")

      assert get_session(conn, :operating_system) == "Android"
    end

    test "does not break if it cannot detect the operating system", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "curl/7.79.1")
        |> get("/")

      refute get_session(conn, :operating_system)
    end

    test "does not break if the User-Agent header is not available", %{conn: conn} do
      conn = get(conn, "/")

      refute get_session(conn, :operating_system)
    end
  end
end

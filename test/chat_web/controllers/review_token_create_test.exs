defmodule ChatWeb.ReviewTokenCreateTest do
  use ChatWeb.ConnCase, async: true
  import Rewire

  defmodule CreatorOk do
    def create(_bot_hash, _origin_order_hash), do: {:ok, "AAAABBBBCCCCDDDDEEEEFFFFGGGG1234"}
  end

  defmodule CreatorNoVouch do
    def create(_bot_hash, _origin_order_hash), do: {:error, :no_live_vouch}
  end

  defmodule WorkerOk do
    def running?(_bot_hash), do: true
    def info(_bot_hash), do: %{bot_hash: "u_bot", origin_hash: "origin_ok"}
    def verify_auth(_bot_hash, "valid-bearer"), do: :ok
    def verify_auth(_bot_hash, _bearer), do: {:error, :invalid_auth_token}
  end

  defmodule WorkerNoAuthConfigured do
    def running?(_bot_hash), do: true
    def info(_bot_hash), do: %{bot_hash: "u_bot", origin_hash: "origin_no_auth"}
    def verify_auth(_bot_hash, _bearer), do: {:error, :no_auth_token_configured}
  end

  defmodule WorkerNotRunning do
    def running?(_bot_hash), do: false
    def info(_bot_hash), do: %{bot_hash: "u_ghost", origin_hash: "origin_ghost"}
    def verify_auth(_bot_hash, _bearer), do: {:error, :invalid_auth_token}
  end

  describe "POST /r/api/token/create" do
    test "returns nonce and url on success with correct bearer", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, Worker: WorkerOk, TokenCreator: CreatorOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer valid-bearer")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => "org_ord_x"})

      assert %{"nonce" => nonce, "url" => url} = json_response(conn, 200)
      assert nonce == "AAAABBBBCCCCDDDDEEEEFFFFGGGG1234"
      assert url =~ "/r/#{nonce}"
    end

    test "returns nonce for reusable token (no origin_order_hash)", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, Worker: WorkerOk, TokenCreator: CreatorOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer valid-bearer")
        |> controller.create(%{"bot_hash" => "u_bot"})

      assert %{"nonce" => _nonce, "url" => _url} = json_response(conn, 200)
    end

    test "returns 401 when bearer is missing", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, Worker: WorkerOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => nil})

      assert %{"error" => "Missing Authorization header"} = json_response(conn, 401)
    end

    test "returns 403 when bearer is wrong", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, Worker: WorkerOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer wrong-bearer")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => nil})

      assert %{"error" => "Invalid auth token"} = json_response(conn, 403)
    end

    test "returns 403 when no auth token configured for the bot", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, Worker: WorkerNoAuthConfigured)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer anything")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => nil})

      assert %{"error" => "No auth token configured for this origin"} = json_response(conn, 403)
    end

    test "returns 404 when bot not running", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, Worker: WorkerNotRunning)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer anything")
        |> controller.create(%{"bot_hash" => "u_ghost", "origin_order_hash" => nil})

      assert %{"error" => "Bot not running"} = json_response(conn, 404)
    end

    test "returns 403 when no live vouch", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, Worker: WorkerOk, TokenCreator: CreatorNoVouch)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer valid-bearer")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => nil})

      assert %{"error" => "No live vouch for this bot"} = json_response(conn, 403)
    end
  end
end

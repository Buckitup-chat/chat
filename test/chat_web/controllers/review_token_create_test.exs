defmodule ChatWeb.ReviewTokenCreateTest do
  use ChatWeb.ConnCase, async: true
  import Rewire

  defmodule CreatorOk do
    def create(_bot_hash, _origin_order_hash), do: {:ok, "AAAABBBBCCCCDDDDEEEEFFFFGGGG1234"}
  end

  defmodule CreatorNotRunning do
    def create(_bot_hash, _origin_order_hash), do: {:error, :bot_not_running}
  end

  defmodule CreatorNoVouch do
    def create(_bot_hash, _origin_order_hash), do: {:error, :no_live_vouch}
  end

  describe "POST /r/api/token/create" do
    test "returns nonce and url on success", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, TokenCreator: CreatorOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => "org_ord_x"})

      assert %{"nonce" => nonce, "url" => url} = json_response(conn, 200)
      assert nonce == "AAAABBBBCCCCDDDDEEEEFFFFGGGG1234"
      assert url =~ "/r/#{nonce}"
    end

    test "returns nonce for reusable token (no origin_order_hash)", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, TokenCreator: CreatorOk)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.create(%{"bot_hash" => "u_bot"})

      assert %{"nonce" => _nonce, "url" => _url} = json_response(conn, 200)
    end

    test "returns 404 when bot not running", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, TokenCreator: CreatorNotRunning)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.create(%{"bot_hash" => "u_ghost", "origin_order_hash" => nil})

      assert %{"error" => "Bot not running"} = json_response(conn, 404)
    end

    test "returns 403 when no live vouch", %{conn: conn} do
      controller = rewire(ChatWeb.ReviewTokenController, TokenCreator: CreatorNoVouch)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.create(%{"bot_hash" => "u_bot", "origin_order_hash" => nil})

      assert %{"error" => "No live vouch for this bot"} = json_response(conn, 403)
    end
  end
end

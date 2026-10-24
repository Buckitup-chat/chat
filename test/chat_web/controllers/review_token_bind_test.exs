defmodule ChatWeb.ReviewTokenBindTest do
  use ChatWeb.ConnCase, async: true
  import Rewire

  defmodule PopOk do
    def context(_params), do: {:ok, %{challenge: "test_challenge", signature: "test_sig"}}
  end

  defmodule PopMissing do
    def context(_params), do: {:error, {:unauthorized, "Missing user PoP auth"}}
  end

  defmodule BinderOrderLinked do
    def bind(_nonce, _user_hash, _pop), do: {:ok, "bound_nonce_order"}
  end

  defmodule BinderReusable do
    def bind(_nonce, _user_hash, _pop), do: {:ok, "bound_nonce_reusable"}
  end

  defmodule BinderTokenNotFound do
    def bind(_nonce, _user_hash, _pop), do: {:error, :token_not_found}
  end

  defmodule BinderTokenDeleted do
    def bind(_nonce, _user_hash, _pop), do: {:error, :token_deleted}
  end

  defmodule BinderReviewerNotFound do
    def bind(_nonce, _user_hash, _pop), do: {:error, :reviewer_not_found}
  end

  defmodule BinderInvalidPop do
    def bind(_nonce, _user_hash, _pop), do: {:error, :invalid_pop}
  end

  defmodule BinderBotNotRunning do
    def bind(_nonce, _user_hash, _pop), do: {:error, :bot_not_running}
  end

  defmodule BinderNoOriginVouch do
    def bind(_nonce, _user_hash, _pop), do: {:error, :no_bot_origin_vouch}
  end

  defmodule BinderNoDeviceVouch do
    def bind(_nonce, _user_hash, _pop), do: {:error, :no_bot_device_vouch}
  end

  defp bind_params(overrides \\ %{}) do
    Map.merge(
      %{
        "nonce" => "test_nonce",
        "user_hash" => "u_reviewer",
        "auth" => %{"challenge_id" => "ch_1", "signature" => "c2ln"}
      },
      overrides
    )
  end

  describe "POST /r/api/token/bind" do
    test "returns nonce and url on order-linked bind", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderOrderLinked)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"nonce" => "bound_nonce_order", "url" => url} = json_response(conn, 200)
      assert url =~ "/r/bound_nonce_order"
    end

    test "returns new nonce on reusable bind", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderReusable)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"nonce" => "bound_nonce_reusable", "url" => url} = json_response(conn, 200)
      assert url =~ "/r/bound_nonce_reusable"
    end

    test "returns 401 when PoP is missing", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController,
          IngestPop: PopMissing,
          TokenBinder: BinderOrderLinked
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Missing user PoP auth"} = json_response(conn, 401)
    end

    test "returns 404 when token not found", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderTokenNotFound)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Token not found"} = json_response(conn, 404)
    end

    test "returns 410 when token deleted", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderTokenDeleted)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Token has been deleted"} = json_response(conn, 410)
    end

    test "returns 404 when reviewer not found", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController,
          IngestPop: PopOk,
          TokenBinder: BinderReviewerNotFound
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Reviewer identity not found"} = json_response(conn, 404)
    end

    test "returns 401 when PoP is invalid", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderInvalidPop)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Invalid proof of possession"} = json_response(conn, 401)
    end

    test "returns 503 when bot not running", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderBotNotRunning)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Review bot not running"} = json_response(conn, 503)
    end

    test "returns 403 when bot lacks origin vouch", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderNoOriginVouch)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Bot lacks origin vouch"} = json_response(conn, 403)
    end

    test "returns 403 when bot lacks device vouch", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderNoDeviceVouch)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Bot lacks device vouch"} = json_response(conn, 403)
    end
  end
end

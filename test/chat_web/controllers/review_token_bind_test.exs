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

  defmodule BinderNotInvitation do
    def bind(_nonce, _user_hash, _pop), do: {:error, :token_not_invitation}
  end

  defmodule BinderAlreadyBound do
    def bind(_nonce, _user_hash, _pop), do: {:error, :token_already_bound}
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

  setup %{conn: conn} do
    %{conn: %{conn | remote_ip: unique_ip()}}
  end

  defp unique_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
  end

  defp bind_params(overrides \\ %{}) do
    Map.merge(
      %{
        "nonce" => "test_nonce",
        "user_hash" => "u_reviewer_#{System.unique_integer([:positive])}",
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

    test "returns 409 for a bound copy", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderNotInvitation)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Token is a bound copy, not an invitation"} = json_response(conn, 409)
    end

    test "returns 409 for a token bound to another user", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderAlreadyBound)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> controller.bind(bind_params())

      assert %{"error" => "Token is already bound to another user"} = json_response(conn, 409)
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

  describe "POST /r/api/token/bind rate limit" do
    setup do
      %{
        controller:
          rewire(ChatWeb.ReviewTokenController, IngestPop: PopOk, TokenBinder: BinderReusable)
      }
    end

    test "returns 429 with retry-after when one IP exceeds the limit", %{
      conn: conn,
      controller: controller
    } do
      for _ <- 1..10 do
        assert %{"nonce" => _} = conn |> controller.bind(bind_params()) |> json_response(200)
      end

      limited = controller.bind(conn, bind_params())

      assert %{"error" => "Too many requests"} = json_response(limited, 429)
      assert [retry_after] = get_resp_header(limited, "retry-after")
      assert String.to_integer(retry_after) >= 1
    end

    test "returns 429 when one user_hash exceeds the limit across IPs", %{controller: controller} do
      params = bind_params(%{"user_hash" => "u_rl_#{System.unique_integer([:positive])}"})

      bind_from_new_ip = fn ->
        controller.bind(%{build_conn() | remote_ip: unique_ip()}, params)
      end

      for _ <- 1..10, do: assert(%{"nonce" => _} = json_response(bind_from_new_ip.(), 200))

      limited = bind_from_new_ip.()

      assert %{"error" => "Too many requests"} = json_response(limited, 429)
      assert [_retry_after] = get_resp_header(limited, "retry-after")
    end

    test "rejects before PoP check when limited", %{conn: conn} do
      controller =
        rewire(ChatWeb.ReviewTokenController, IngestPop: PopMissing, TokenBinder: BinderReusable)

      for _ <- 1..10, do: assert(json_response(controller.bind(conn, bind_params()), 401))

      assert %{"error" => "Too many requests"} =
               conn |> controller.bind(bind_params()) |> json_response(429)
    end
  end
end

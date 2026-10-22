defmodule ChatWeb.ReviewTokenControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase
  import Rewire

  alias Chat.Data.Schemas.ReviewWriteToken

  defmodule MockTokenNil do
    def get_review_write_token(_nonce), do: nil
  end

  defmodule MockTokenDeleted do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{nonce: "test", deleted_flag: true, owner_timestamp: 1}
    end
  end

  defmodule MockTokenPending do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{
        nonce: "test",
        origin_hash: "origin",
        review_bot_hash: "bot",
        deleted_flag: false,
        user_hash: nil,
        review_hash: nil,
        owner_timestamp: 1,
        sign_b64: "sig",
        sign_hash: "hash"
      }
    end
  end

  defmodule MockTokenBound do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{
        nonce: "test",
        origin_hash: "origin",
        review_bot_hash: "bot",
        deleted_flag: false,
        user_hash: "user",
        review_hash: nil,
        owner_timestamp: 1,
        sign_b64: "sig",
        sign_hash: "hash"
      }
    end
  end

  defmodule MockTokenReviewed do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{
        nonce: "test",
        origin_hash: "origin",
        review_bot_hash: "bot",
        deleted_flag: false,
        user_hash: "user",
        review_hash: "review",
        owner_timestamp: 1,
        sign_b64: "sig",
        sign_hash: "hash"
      }
    end
  end

  test "returns 410 for nonexistent nonce", %{conn: conn} do
    controller = rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: MockTokenNil)
    conn = controller.show(conn, %{"nonce" => "nonexistent"})

    assert conn.status == 410
    assert conn.resp_body =~ "expired"
  end

  test "returns 410 for soft-deleted token", %{conn: conn} do
    controller = rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: MockTokenDeleted)
    conn = controller.show(conn, %{"nonce" => "deleted"})

    assert conn.status == 410
    assert conn.resp_body =~ "expired"
  end

  test "serves SPA for pending token", %{conn: conn} do
    controller = rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: MockTokenPending)
    conn = controller.show(conn, %{"nonce" => "pending"})

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
  end

  test "serves SPA for bound token", %{conn: conn} do
    controller = rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: MockTokenBound)
    conn = controller.show(conn, %{"nonce" => "bound"})

    assert conn.status == 200
  end

  test "serves SPA for reviewed token", %{conn: conn} do
    controller = rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: MockTokenReviewed)
    conn = controller.show(conn, %{"nonce" => "reviewed"})

    assert conn.status == 200
  end
end

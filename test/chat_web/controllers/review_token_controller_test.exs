defmodule ChatWeb.ReviewTokenControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase
  import Support.Rewire

  alias Chat.Data.Schemas.ReviewWriteToken

  defmodule MockTokenNil do
    def get_review_write_token(_nonce), do: nil
  end

  defmodule MockTokenDeleted do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{nonce_hash: "rwn_test", deleted_flag: true, owner_timestamp: 1}
    end
  end

  defmodule MockTokenPending do
    def get_review_write_token(_nonce) do
      %ReviewWriteToken{
        nonce_hash: "rwn_test",
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
        nonce_hash: "rwn_test",
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
        nonce_hash: "rwn_test",
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

  defmodule MockTokenByHash do
    alias Chat.Data.Types.ReviewWriteTokenNonceHash

    def get_review_write_token(nonce_hash) do
      if nonce_hash == ReviewWriteTokenNonceHash.from_nonce("pending"),
        do: %ReviewWriteToken{nonce_hash: nonce_hash, deleted_flag: false, owner_timestamp: 1}
    end
  end

  # No review bot is started here: `/r/:nonce` must not need one

  defmodule ReviewWriteTokenStub do
    def get_review_write_token(a1),
      do: Process.get({:mock, :ReviewWriteToken}).get_review_write_token(a1)
  end

  # One rewire per file: Rewire names each rewired module <Target>.R<random 0..10_000>
  # at compile time, so many rewires of one target collide and overwrite each other.
  rewire(ChatWeb.ReviewTokenController, ReviewWriteToken: ReviewWriteTokenStub, as: Controller)

  test "looks the token up by nonce hash", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenByHash)

    assert controller.show(conn, %{"nonce" => "pending"}).status == 200
    assert controller.show(build_conn(), %{"nonce" => "other"}).status == 410
  end

  test "returns 410 for nonexistent nonce", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenNil)
    conn = controller.show(conn, %{"nonce" => "nonexistent"})

    assert conn.status == 410
    assert conn.resp_body =~ "expired"
  end

  test "returns 410 for soft-deleted token", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenDeleted)
    conn = controller.show(conn, %{"nonce" => "deleted"})

    assert conn.status == 410
    assert conn.resp_body =~ "expired"
  end

  test "serves SPA for pending token", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenPending)
    conn = controller.show(conn, %{"nonce" => "pending"})

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
  end

  test "serves SPA for bound token", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenBound)
    conn = controller.show(conn, %{"nonce" => "bound"})

    assert conn.status == 200
  end

  test "serves SPA for reviewed token", %{conn: conn} do
    controller = with_mocks(ReviewWriteToken: MockTokenReviewed)
    conn = controller.show(conn, %{"nonce" => "reviewed"})

    assert conn.status == 200
  end

  # Helpers

  defp with_mocks(mocks) do
    Enum.each(mocks, fn {dep, mock} -> Process.put({:mock, dep}, mock) end)
    Controller
  end
end

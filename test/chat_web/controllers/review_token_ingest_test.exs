defmodule ChatWeb.ReviewTokenIngestTest do
  @moduledoc """
  Review ingest gated by the exact bind vouch, end to end: real bot, real
  `/r/api/token/bind`, real Writer on `/electric/v1/ingest`.

  Tokens are reusable roots: each bind mints a bound copy with its own nonce.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReviewBotFixtures
  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1]

  import Chat.Test.ReviewGateFixtures,
    only: [set_review_access: 2]

  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.User
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()

    setup_origin_with_bot()
    |> Map.put(:conn, Sandbox.init_test_session(conn, Chat.Repo))
    |> tap(&start_bot!/1)
  end

  test "two bound tokens: each review links to the token whose nonce it carried", ctx do
    nonce_a = ctx |> create_token!() |> then(&bind_token!(ctx, &1))
    nonce_b = ctx |> create_token!() |> then(&bind_token!(ctx, &1))

    {resp_b, review_b} = post_review(ctx, nonce_b)
    {resp_a, review_a} = post_review(ctx, nonce_a)

    assert %{"txid" => _} = json_response(resp_a, 200)
    assert %{"txid" => _} = json_response(resp_b, 200)
    assert token(nonce_a).review_hash == review_a
    assert token(nonce_b).review_hash == review_b
  end

  test "second review with the nonce of a used token is rejected", ctx do
    nonce = ctx |> create_token!() |> then(&bind_token!(ctx, &1))

    {first, _} = post_review(ctx, nonce)
    assert first.status == 200

    {second, _} = post_review(ctx, nonce)
    assert second.status == 400
    assert second.resp_body == "token already used"
  end

  test "nonce of a token bound to another user is rejected", ctx do
    other = User.generate_pq_identity("Other")
    insert_user_card(other)

    nonce =
      ctx |> create_token!() |> then(&bind_token!(ctx, &1, other))

    {resp, _} = post_review(ctx, nonce)
    assert resp.status == 400
    assert resp.resp_body == "token mismatch"
  end

  describe "invite_only" do
    setup ctx do
      set_review_access(ctx.origin_hash, "invite_only")
      :ok
    end

    test "token-only author is rejected without a nonce", ctx do
      ctx |> create_token!() |> then(&bind_token!(ctx, &1))

      {resp, _} = post_review(ctx, nil)
      assert resp.status == 400
      assert resp.resp_body == "nonce required"
    end

    test "token-only author is accepted with the bound nonce", ctx do
      nonce = ctx |> create_token!() |> then(&bind_token!(ctx, &1))

      {resp, review_hash} = post_review(ctx, nonce)
      assert %{"txid" => _} = json_response(resp, 200)
      assert token(nonce).review_hash == review_hash
    end
  end

  describe "GET /r/:nonce" do
    test "bound and reviewed token still serves the app (SPA picks the branch)", ctx do
      nonce = ctx |> create_token!() |> then(&bind_token!(ctx, &1))
      {%{status: 200}, _} = post_review(ctx, nonce)

      assert ctx.conn |> get("/r/#{nonce}") |> Map.get(:status) == 200
    end
  end

  # --- Helpers ---

  defp token(nonce),
    do: nonce |> ReviewWriteTokenNonceHash.from_nonce() |> TokenData.get_review_write_token()
end

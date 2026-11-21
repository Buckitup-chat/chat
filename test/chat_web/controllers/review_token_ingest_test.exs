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
    only: [insert_bind_vouch: 4, insert_bound_token: 3, set_review_access: 2]

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
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

  # A second HTTP bind by the same reviewer trips on existing device vouches
  # (TokenBinder, #839), so the second bound copy is stored directly.
  test "two bound tokens: each review links to the token whose nonce it carried", ctx do
    nonce_a = ctx |> create_token!() |> then(&bind_token!(ctx, &1))
    nonce_b = insert_bound_token(ctx.bot_identity, ctx.origin_hash, ctx.reviewer_card.user_hash)
    insert_bind_vouch(ctx.bot_identity, ctx.origin_hash, ctx.reviewer_card.user_hash, nonce_b)

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

  defp post_review(ctx, nonce) do
    {mutation, review_hash} = review_insert_mutation(ctx.reviewer, ctx.origin_hash)
    {challenge_id, challenge} = Challenge.store()
    signature = challenge |> EnigmaPq.sign(ctx.reviewer.sign_skey) |> b64()

    auth =
      %{"challenge_id" => challenge_id, "signature" => signature}
      |> then(&if nonce, do: Map.put(&1, "nonce", nonce), else: &1)

    resp =
      ctx.conn
      |> put_req_header("content-type", "application/json")
      |> post("/electric/v1/ingest", Jason.encode!(%{"auth" => auth, "mutations" => [mutation]}))

    {resp, review_hash}
  end

  defp review_insert_mutation(author, origin_hash) do
    author_hash = User.extract_pq_card(author).user_hash
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    content_b64 = EnigmaPq.aes_gcm_encrypt("Great place!", :crypto.strong_rand_bytes(32))
    timestamp = System.os_time(:millisecond)

    sign_b64 =
      %Review{
        review_hash: review_hash,
        origin_hash: origin_hash,
        author_hash: author_hash,
        content_b64: content_b64,
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: timestamp
      }
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(author.sign_skey)

    mutation = %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author_hash,
        "content_b64" => b64(content_b64),
        "deleted_flag" => false,
        "parent_sign_hash" => nil,
        "owner_timestamp" => timestamp,
        "sign_b64" => b64(sign_b64),
        "sign_hash" => sign_b64 |> EnigmaPq.hash() |> ReviewSignHash.from_binary()
      },
      "syncMetadata" => %{"relation" => "review"}
    }

    {mutation, review_hash}
  end
end

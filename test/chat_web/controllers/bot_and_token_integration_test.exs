defmodule ChatWeb.BotAndTokenIntegrationTest do
  @moduledoc """
  End-to-end integration test for the review bot lifecycle and write token
  creation/bind flow, exercising the full HTTP path.

  Covers:
  - Bot startup via DynamicSupervisor, auth token verification
  - Write token creation via POST /r/api/token/create
  - Write token bind via POST /r/api/token/bind (with real PoP)
  - Vouches issued by bind (origin + device scoped)
  - review_write_tokens shape read gating in trust mode
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers,
    only: [put_gate: 2, open_read_session!: 4, with_bearer: 2]

  import Chat.Test.ReviewBotFixtures
  import ChatWeb.LiveTestHelpers, only: [wait_until: 3]

  alias Chat.Challenge
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.DeviceId
  alias Chat.ReviewBot.Worker
  alias Chat.Test.ReadGateHelpers
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()

    setup_origin_with_bot()
    |> Map.put(:conn, Sandbox.init_test_session(conn, Chat.Repo))
  end

  describe "bot lifecycle" do
    test "bot starts and responds to info/verify_auth", ctx do
      start_bot!(ctx)

      assert Worker.running?(ctx.bot_hash)
      assert %{origin_hash: oh} = Worker.info(ctx.bot_hash)
      assert oh == ctx.origin_hash

      assert :ok = Worker.verify_auth(ctx.bot_hash, auth_token())
      assert {:error, :invalid_auth_token} = Worker.verify_auth(ctx.bot_hash, "wrong")
    end

    test "bot stops cleanly", ctx do
      start_bot!(ctx)
      assert Worker.running?(ctx.bot_hash)

      pid = Worker.whereis(ctx.bot_hash)
      DynamicSupervisor.terminate_child(Chat.ReviewBot.WorkerSupervisor, pid)

      # Registry drops the entry asynchronously after the process exits
      assert :ok =
               wait_until(fn -> not Worker.running?(ctx.bot_hash) end, "bot stopped",
                 interval: 10
               )
    end
  end

  describe "POST /r/api/token/create" do
    test "creates token with valid auth", ctx do
      start_bot!(ctx)

      assert %{"nonce" => nonce, "url" => url} =
               ctx.conn
               |> put_req_header("authorization", "Bearer #{auth_token()}")
               |> put_req_header("content-type", "application/json")
               |> post("/r/api/token/create", Jason.encode!(%{"bot_hash" => ctx.bot_hash}))
               |> json_response(200)

      assert is_binary(nonce)
      assert url =~ "/r/#{nonce}"
    end

    test "rejects without auth header", ctx do
      start_bot!(ctx)

      assert %{"error" => "Missing Authorization header"} =
               ctx.conn
               |> put_req_header("content-type", "application/json")
               |> post("/r/api/token/create", Jason.encode!(%{"bot_hash" => ctx.bot_hash}))
               |> json_response(401)
    end

    test "rejects with wrong auth token", ctx do
      start_bot!(ctx)

      assert %{"error" => "Invalid auth token"} =
               ctx.conn
               |> put_req_header("authorization", "Bearer wrong-token")
               |> put_req_header("content-type", "application/json")
               |> post("/r/api/token/create", Jason.encode!(%{"bot_hash" => ctx.bot_hash}))
               |> json_response(403)
    end

    test "rejects when bot not running", ctx do
      assert %{"error" => "Bot not running"} =
               ctx.conn
               |> put_req_header("authorization", "Bearer #{auth_token()}")
               |> put_req_header("content-type", "application/json")
               |> post("/r/api/token/create", Jason.encode!(%{"bot_hash" => ctx.bot_hash}))
               |> json_response(404)
    end
  end

  describe "POST /r/api/token/bind" do
    test "binds reviewer to reusable token and issues vouches", ctx do
      start_bot!(ctx)
      parent_nonce = create_token!(ctx)

      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(ctx.reviewer.sign_skey) |> b64()

      assert %{"nonce" => bound_nonce, "url" => url} =
               ctx.conn
               |> put_req_header("content-type", "application/json")
               |> post(
                 "/r/api/token/bind",
                 Jason.encode!(%{
                   "nonce" => parent_nonce,
                   "user_hash" => ctx.reviewer_card.user_hash,
                   "auth" => %{
                     "challenge_id" => challenge_id,
                     "signature" => signature
                   }
                 })
               )
               |> json_response(200)

      assert bound_nonce != parent_nonce
      assert url =~ "/r/#{bound_nonce}"

      origin_kind =
        "origins.#{ctx.origin_hash}.reviews.write.#{ReviewWriteTokenNonceHash.from_nonce(bound_nonce)}"

      assert %{deleted_flag: false} =
               VouchTokenData.get_vouch_token(
                 origin_kind,
                 ctx.bot_hash,
                 ctx.reviewer_card.user_hash
               )

      device_kind = "device.#{DeviceId.id()}.storage.write.review"

      assert %{deleted_flag: false} =
               VouchTokenData.get_vouch_token(
                 device_kind,
                 ctx.bot_hash,
                 ctx.reviewer_card.user_hash
               )
    end

    test "rejects bind when bot is not running", ctx do
      start_bot!(ctx)
      nonce = create_token!(ctx)
      stop_bot!(ctx.bot_hash)

      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(ctx.reviewer.sign_skey) |> b64()

      assert %{"error" => "Review bot not running"} =
               ctx.conn
               |> put_req_header("content-type", "application/json")
               |> post(
                 "/r/api/token/bind",
                 Jason.encode!(%{
                   "nonce" => nonce,
                   "user_hash" => ctx.reviewer_card.user_hash,
                   "auth" => %{
                     "challenge_id" => challenge_id,
                     "signature" => signature
                   }
                 })
               )
               |> json_response(503)
    end
  end

  describe "plaintext nonce exposure" do
    test "no /shapes response and no stored row holds a plaintext nonce", ctx do
      start_bot!(ctx)
      put_gate(:open, ctx.owner_card)
      parent_nonce = create_token!(ctx)
      bound_nonce = bind_token!(ctx, parent_nonce)
      nonces = [parent_nonce, bound_nonce]

      tokens_body = get_shape(ctx.conn, "review_write_tokens").resp_body
      assert tokens_body =~ ReviewWriteTokenNonceHash.from_nonce(parent_nonce)
      assert tokens_body =~ ReviewWriteTokenNonceHash.from_nonce(bound_nonce)

      vouches_body = get_shape(ctx.conn, "vouch_tokens").resp_body
      assert vouches_body =~ ReviewWriteTokenNonceHash.from_nonce(bound_nonce)

      stored =
        [ReviewWriteToken, VouchToken]
        |> Enum.flat_map(&Chat.Repo.all/1)
        |> :erlang.term_to_binary()

      for haystack <- [tokens_body, vouches_body, stored], nonce <- nonces do
        refute haystack =~ nonce
      end
    end
  end

  describe "review_write_tokens read gating" do
    test "open mode — shape readable without session", ctx do
      put_gate(:open, ctx.owner_card)
      assert get_shape(ctx.conn, "review_write_tokens").status == 200
    end

    test "trust mode — shape requires read session", ctx do
      put_gate(:trust, ctx.owner_card)

      assert %{"error" => "read_session_required", "shape" => "review_write_token"} =
               ctx.conn |> get_shape("review_write_tokens") |> json_response(401)
    end

    test "trust mode — read vouch enables access", ctx do
      put_gate(:trust, ctx.owner_card)

      ReadGateHelpers.vouch(
        ctx.owner,
        ctx.owner_card.user_hash,
        ctx.reviewer_card.user_hash,
        "storage.read"
      )

      token =
        open_read_session!(
          ctx.conn,
          ctx.reviewer_card.user_hash,
          "review_write_token",
          ctx.reviewer.sign_skey
        )

      assert ctx.conn
             |> with_bearer(token)
             |> get_shape("review_write_tokens")
             |> Map.get(:status) == 200
    end
  end

  # --- Private helpers ---

  defp get_shape(conn, table),
    do: get(conn, "/electric/v1/shapes", %{"table" => table, "offset" => "-1"})
end

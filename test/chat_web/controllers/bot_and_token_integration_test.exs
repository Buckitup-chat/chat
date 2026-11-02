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
    only: [put_gate: 2, identity_with_card: 1, open_read_session!: 4, with_bearer: 2]

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1]

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.DeviceId
  alias Chat.ReviewBot.Identity
  alias Chat.ReviewBot.Worker
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Phoenix.Sync.Sandbox

  @auth_token "super-secret-token-1234"

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)

    start_supervised!({Registry, keys: :unique, name: Chat.ReviewBot.Registry})
    start_supervised!({DynamicSupervisor, name: Chat.ReviewBot.WorkerSupervisor, strategy: :one_for_one})

    {owner, owner_card} = identity_with_card("Owner")
    {reviewer, reviewer_card} = identity_with_card("Reviewer")

    origin_identity = User.generate_pq_identity("TestOrigin")
    origin_card = insert_user_card(origin_identity)
    _origin = Chat.Test.ReviewFixtures.insert_origin(origin_identity, owner, :none)
    origin_hash = origin_card.user_hash

    bot_identity = User.generate_pq_identity("ReviewBot_TestOrigin")
    bot_card = insert_user_card(bot_identity)
    bot_hash = bot_card.user_hash

    {secret, encrypted_identity} = Identity.wrap(bot_identity, origin_card.crypt_pkey)
    {_auth_secret, encrypted_auth} = Identity.wrap_token(@auth_token, origin_card.crypt_pkey)

    origin_bot = %OriginBot{
      bot_hash: bot_hash,
      origin_hash: origin_hash,
      secret_b64: secret,
      encrypted_identity_b64: encrypted_identity,
      encrypted_auth_token_b64: encrypted_auth,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed_bot = sign_with_hash(origin_bot, origin_identity.sign_skey, &OriginBotSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:origin_bot, :insert, signed_bot)

    origin_vouch = %VouchToken{
      kind: "origins.#{origin_hash}.reviews.write",
      issuer_hash: origin_hash,
      subject_hash: bot_hash,
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    origin_vouch = sign_with_key(origin_vouch, origin_identity.sign_skey)

    {:ok, _} =
      origin_vouch
      |> Map.from_struct()
      |> then(&VouchToken.create_changeset(%VouchToken{}, &1))
      |> VouchTokenData.upsert_vouch_token()

    owner_vouch = %VouchToken{
      kind: "device.#{DeviceId.id()}.storage.write.review_write_token",
      issuer_hash: owner_card.user_hash,
      subject_hash: bot_hash,
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    owner_vouch = sign_with_key(owner_vouch, owner.sign_skey)

    {:ok, _} =
      owner_vouch
      |> Map.from_struct()
      |> then(&VouchToken.create_changeset(%VouchToken{}, &1))
      |> VouchTokenData.upsert_vouch_token()

    conn = Sandbox.init_test_session(conn, Chat.Repo)

    %{
      conn: conn,
      owner: owner,
      owner_card: owner_card,
      reviewer: reviewer,
      reviewer_card: reviewer_card,
      origin_identity: origin_identity,
      origin_card: origin_card,
      origin_hash: origin_hash,
      bot_identity: bot_identity,
      bot_card: bot_card,
      bot_hash: bot_hash,
      signed_bot: %{
        bot_hash: bot_hash,
        origin_hash: origin_hash,
        secret_b64: secret,
        encrypted_identity_b64: encrypted_identity,
        encrypted_auth_token_b64: encrypted_auth,
        deleted_flag: false,
        owner_timestamp: signed_bot.owner_timestamp,
        sign_hash: signed_bot.sign_hash
      },
    }
  end

  describe "bot lifecycle" do
    test "bot starts and responds to info/verify_auth", ctx do
      start_bot!(ctx)

      assert Worker.running?(ctx.bot_hash)
      assert %{origin_hash: oh} = Worker.info(ctx.bot_hash)
      assert oh == ctx.origin_hash

      assert :ok = Worker.verify_auth(ctx.bot_hash, @auth_token)
      assert {:error, :invalid_auth_token} = Worker.verify_auth(ctx.bot_hash, "wrong")
    end

    test "bot stops cleanly", ctx do
      start_bot!(ctx)
      assert Worker.running?(ctx.bot_hash)

      pid = Worker.whereis(ctx.bot_hash)
      DynamicSupervisor.terminate_child(Chat.ReviewBot.WorkerSupervisor, pid)

      refute Worker.running?(ctx.bot_hash)
    end
  end

  describe "POST /r/api/token/create" do
    test "creates token with valid auth", ctx do
      start_bot!(ctx)

      assert %{"nonce" => nonce, "url" => url} =
               ctx.conn
               |> put_req_header("authorization", "Bearer #{@auth_token}")
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
               |> put_req_header("authorization", "Bearer #{@auth_token}")
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

      origin_kind = "origins.#{ctx.origin_hash}.reviews.write.#{bound_nonce}"

      assert %{deleted_flag: false} =
               VouchTokenData.get_vouch_token(origin_kind, ctx.bot_hash, ctx.reviewer_card.user_hash)

      device_kind = "device.#{DeviceId.id()}.storage.write.review"

      assert %{deleted_flag: false} =
               VouchTokenData.get_vouch_token(device_kind, ctx.bot_hash, ctx.reviewer_card.user_hash)
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

      Chat.Test.ReadGateHelpers.vouch(
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

      assert ctx.conn |> with_bearer(token) |> get_shape("review_write_tokens") |> Map.get(:status) == 200
    end
  end

  # --- Private helpers ---

  defp start_bot!(ctx) do
    {:ok, identity} =
      Identity.unwrap(
        ctx.signed_bot.secret_b64,
        ctx.signed_bot.encrypted_identity_b64,
        ctx.origin_identity.crypt_skey
      )

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Chat.ReviewBot.WorkerSupervisor,
        {Worker,
         %{
           bot_hash: ctx.bot_hash,
           origin_hash: ctx.origin_hash,
           identity: identity,
           auth_token: @auth_token
         }}
      )
  end

  defp stop_bot!(bot_hash) do
    pid = Worker.whereis(bot_hash)
    DynamicSupervisor.terminate_child(Chat.ReviewBot.WorkerSupervisor, pid)
  end

  defp create_token!(ctx, opts \\ []) do
    order_hash = Keyword.get(opts, :origin_order_hash)

    body = %{"bot_hash" => ctx.bot_hash}
    body = if order_hash, do: Map.put(body, "origin_order_hash", order_hash), else: body

    %{"nonce" => nonce} =
      ctx.conn
      |> put_req_header("authorization", "Bearer #{@auth_token}")
      |> put_req_header("content-type", "application/json")
      |> post("/r/api/token/create", Jason.encode!(body))
      |> json_response(200)

    nonce
  end

  defp get_shape(conn, table),
    do: get(conn, "/electric/v1/shapes", %{"table" => table, "offset" => "-1"})

  defp sign_with_hash(struct, sign_skey, hash_fn) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_fn.()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp b64(bin), do: Base.encode64(bin, padding: false)
end

defmodule Chat.Test.ReviewBotFixtures do
  @moduledoc """
  Origin + review bot setup for HTTP integration tests: origin bot row,
  origin→bot and owner→bot vouches, a running `Worker`, token create/bind
  through `/r/api/token/*`. Call `start_bot_registry!/0` from `setup` first.
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import Phoenix.ConnTest
  import Plug.Conn

  import Chat.Test.ReadGateHelpers, only: [identity_with_card: 1]

  import Chat.Test.ReviewFixtures,
    only: [insert_user_card: 1, sign_with_hash: 3, sign_with_key: 2]

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.DeviceId
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.ReviewBot.Identity
  alias Chat.ReviewBot.Worker
  alias Chat.Test.ReviewFixtures

  @endpoint ChatWeb.Endpoint
  @auth_token "super-secret-token-1234"

  def auth_token, do: @auth_token

  def start_bot_registry! do
    start_supervised!({Registry, keys: :unique, name: Chat.ReviewBot.Registry})

    start_supervised!(
      {DynamicSupervisor, name: Chat.ReviewBot.WorkerSupervisor, strategy: :one_for_one}
    )
  end

  @doc "Owner, reviewer, origin and its bot (row + vouches). Returns the test context map."
  def setup_origin_with_bot do
    {owner, owner_card} = identity_with_card("Owner")
    {reviewer, reviewer_card} = identity_with_card("Reviewer")

    origin_identity = User.generate_pq_identity("TestOrigin")
    origin_card = insert_user_card(origin_identity)
    _origin = ReviewFixtures.insert_origin(origin_identity, owner, :none)
    origin_hash = origin_card.user_hash

    bot_identity = User.generate_pq_identity("ReviewBot_TestOrigin")
    bot_card = insert_user_card(bot_identity)
    bot_hash = bot_card.user_hash

    {secret, encrypted_identity} = Identity.wrap(bot_identity, origin_card.crypt_pkey)
    {_auth_secret, encrypted_auth} = Identity.wrap_token(@auth_token, origin_card.crypt_pkey)

    signed_bot =
      %OriginBot{
        bot_hash: bot_hash,
        origin_hash: origin_hash,
        secret_b64: secret,
        encrypted_identity_b64: encrypted_identity,
        encrypted_auth_token_b64: encrypted_auth,
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      }
      |> sign_with_hash(origin_identity.sign_skey, &OriginBotSignHash.from_binary/1)

    {:ok, _} = ShapeWriter.write(:origin_bot, :insert, signed_bot)

    upsert_vouch!(origin_identity, origin_hash, bot_hash, "origins.#{origin_hash}.reviews.write")

    upsert_vouch!(
      owner,
      owner_card.user_hash,
      bot_hash,
      "device.#{DeviceId.id()}.storage.write.review_write_token"
    )

    %{
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
      signed_bot:
        Map.take(signed_bot, [
          :bot_hash,
          :origin_hash,
          :secret_b64,
          :encrypted_identity_b64,
          :encrypted_auth_token_b64,
          :deleted_flag,
          :owner_timestamp,
          :sign_hash
        ])
    }
  end

  def start_bot!(ctx) do
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

  def stop_bot!(bot_hash) do
    pid = Worker.whereis(bot_hash)
    DynamicSupervisor.terminate_child(Chat.ReviewBot.WorkerSupervisor, pid)
  end

  def create_token!(ctx, opts \\ []) do
    body =
      case Keyword.get(opts, :origin_order_hash) do
        nil -> %{"bot_hash" => ctx.bot_hash}
        order_hash -> %{"bot_hash" => ctx.bot_hash, "origin_order_hash" => order_hash}
      end

    %{"nonce" => nonce} =
      ctx.conn
      |> put_req_header("authorization", "Bearer #{@auth_token}")
      |> put_req_header("content-type", "application/json")
      |> post("/r/api/token/create", Jason.encode!(body))
      |> json_response(200)

    nonce
  end

  def bind_token!(ctx, nonce, reviewer \\ nil) do
    reviewer = reviewer || ctx.reviewer
    {challenge_id, challenge} = Challenge.store()
    signature = challenge |> EnigmaPq.sign(reviewer.sign_skey) |> b64()

    body = %{
      "nonce" => nonce,
      "user_hash" => User.extract_pq_card(reviewer).user_hash,
      "auth" => %{"challenge_id" => challenge_id, "signature" => signature}
    }

    %{"nonce" => bound_nonce} =
      ctx.conn
      |> put_req_header("content-type", "application/json")
      |> post("/r/api/token/bind", Jason.encode!(body))
      |> json_response(200)

    bound_nonce
  end

  @doc "Posts a signed review insert to `/electric/v1/ingest`, with `nonce` in auth when given."
  def post_review(ctx, nonce) do
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

  def b64(bin), do: Base.encode64(bin, padding: false)

  defp upsert_vouch!(issuer_identity, issuer_hash, subject_hash, kind) do
    {:ok, _} =
      %VouchToken{
        kind: kind,
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: System.os_time(:millisecond),
        deleted_flag: false
      }
      |> sign_with_key(issuer_identity.sign_skey)
      |> Map.from_struct()
      |> then(&VouchToken.create_changeset(%VouchToken{}, &1))
      |> VouchTokenData.upsert_vouch_token()
  end
end

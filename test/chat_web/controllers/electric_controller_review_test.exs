defmodule ChatWeb.ElectricControllerReviewTest do
  @moduledoc """
  HTTP ingest (`POST /electric/v1/ingest`) of reviews: insert with proof-of-possession auth,
  the `invite_only` origin gate, nonce-based write-token linking and signed updates.

  Review lists and public passwords live in `ElectricControllerReviewPasswordTest`, origin
  moderation in `ElectricControllerReviewModerationTest`.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers,
    only: [post_ingest: 3, signature_and_hash: 3, to_base64: 1]

  import Chat.Test.ElectricReviewIngestFixtures
  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]

  alias Chat.Challenge
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewWriteToken
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.User, as: UserData
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.Test.ReviewGateFixtures
  alias EnigmaPq

  setup %{conn: conn}, do: review_ingest_parties(conn, :none)

  describe "review insert" do
    test "persists a signed review via HTTP ingest", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash) != nil
    end

    test "rejects a review whose PoP is signed by someone other than the author", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      wrong_signer = UserData.generate_pq_identity("Impostor")
      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, wrong_signer.sign_skey)

      assert conn.status in [400, 401, 422], conn.resp_body
      assert ReviewData.get_review(review_hash) == nil
    end
  end

  describe "review insert (invite_only gate in check phase)" do
    setup ctx do
      Repo.insert!(%Chat.Data.Schemas.OriginSetting{
        origin_hash: ctx.origin_hash,
        key: "review_access",
        value: "invite_only",
        deleted_flag: false,
        owner_timestamp: 1,
        sign_b64: <<0::256>>
      })

      :ok
    end

    test "rejects review without vouch before validation", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 401, 422], conn.resp_body
      assert ReviewData.get_review(review_hash) == nil
    end

    test "accepts review when author has token-scoped vouch", ctx do
      nonce = "tok_http_test"
      insert_origin_vouch(ctx.origin_identity, ctx.origin_hash, ctx.author_hash, nonce)

      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash) != nil
    end
  end

  describe "review insert with nonce-based token linking" do
    test "links token review_hash atomically on insert", ctx do
      nonce = insert_bound_token(ctx.origin_hash, ctx.author_hash)

      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn =
        post_ingest_with_nonce(
          ctx.conn,
          %{"mutations" => [mutation]},
          ctx.author.sign_skey,
          nonce
        )

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash) != nil

      token =
        nonce
        |> ReviewWriteTokenNonceHash.from_nonce()
        |> ReviewWriteToken.get_review_write_token()

      assert token.review_hash == review_hash
    end

    test "rejects insert when nonce token not found", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn =
        post_ingest_with_nonce(
          ctx.conn,
          %{"mutations" => [mutation]},
          ctx.author.sign_skey,
          "nonexistent"
        )

      assert conn.status in [400, 401, 422], conn.resp_body
      assert ReviewData.get_review(review_hash) == nil
    end

    test "works normally when no nonce provided", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash) != nil
    end
  end

  describe "review update" do
    test "persists a newer signed version (soft delete) via HTTP ingest", ctx do
      {review_hash, insert_mutation, parent_sign_hash} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [insert_mutation]}, ctx.author.sign_skey).status ==
               200

      update_mutation = build_review_update_mutation(ctx, review_hash, parent_sign_hash)
      conn = post_ingest(ctx.conn, %{"mutations" => [update_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash).deleted_flag == true
    end

    test "rejects an update whose parent_sign_hash is not the current version", ctx do
      {review_hash, insert_mutation, _sign_hash} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [insert_mutation]}, ctx.author.sign_skey).status ==
               200

      stale_parent = :crypto.strong_rand_bytes(64) |> ReviewSignHash.from_binary()
      update_mutation = build_review_update_mutation(ctx, review_hash, stale_parent)
      conn = post_ingest(ctx.conn, %{"mutations" => [update_mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 422], conn.resp_body
      assert ReviewData.get_review(review_hash).deleted_flag == false
    end
  end

  # --- Builders ---

  defp build_review_update_mutation(ctx, review_hash, parent_sign_hash) do
    ts = System.os_time(:millisecond) + 1000
    content = :crypto.strong_rand_bytes(48)

    review = %Review{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      author_hash: ctx.author_hash,
      content_b64: content,
      deleted_flag: true,
      parent_sign_hash: parent_sign_hash,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} =
      signature_and_hash(review, ctx.author.sign_skey, &ReviewSignHash.from_binary/1)

    %{
      "type" => "update",
      "original" => %{"review_hash" => review_hash, "author_hash" => ctx.author_hash},
      "changes" => %{
        "content_b64" => to_base64(content),
        "deleted_flag" => true,
        "parent_sign_hash" => parent_sign_hash,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }
  end

  defp post_ingest_with_nonce(conn, payload, sign_skey, nonce) do
    {challenge_id, challenge} = Challenge.store()

    signature_b64 = challenge |> EnigmaPq.sign(sign_skey) |> Base.encode64(padding: false)

    payload =
      Map.put(payload, "auth", %{
        "challenge_id" => challenge_id,
        "signature" => signature_b64,
        "nonce" => nonce
      })

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end

  defp insert_bound_token(origin_hash, user_hash) do
    bot = UserData.generate_pq_identity("TestBot")
    insert_user_card(bot)
    nonce = ReviewGateFixtures.insert_bound_token(bot, origin_hash, user_hash)
    ReviewGateFixtures.insert_bind_vouch(bot, origin_hash, user_hash, nonce)
    nonce
  end

  defp insert_origin_vouch(origin_identity, origin_hash, author_hash, nonce) do
    issuer_hash = UserData.extract_pq_card(origin_identity).user_hash

    vt =
      %VouchToken{
        kind: "origins.#{origin_hash}.reviews.write.#{nonce}",
        issuer_hash: issuer_hash,
        subject_hash: author_hash,
        owner_timestamp: System.os_time(:millisecond),
        deleted_flag: false
      }
      |> sign_with_key(origin_identity.sign_skey)

    {:ok, _} =
      VouchTokenData.upsert_vouch_token(
        VouchToken.create_changeset(%VouchToken{}, Map.from_struct(vt))
      )
  end
end

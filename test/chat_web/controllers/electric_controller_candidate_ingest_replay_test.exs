defmodule ChatWeb.ElectricControllerCandidateIngestReplayTest do
  @moduledoc """
  Ingest-triggered review promotion via `POST /electric/v1/ingest`: idempotency of replayed
  candidates and signatures, and several candidate mutations in a single ingest call.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3]
  import Chat.Test.ReviewCandidateIngestFixtures

  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData

  setup :candidate_ingest_parties

  # --- Idempotency / replay ---

  describe "idempotency: none mode duplicate candidate" do
    setup ctx, do: origin_with_review(ctx, :none)

    test "same password candidate ingested twice → first 200, second rejected, password published",
         ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)
      refute conn.status == 200

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end
  end

  describe "idempotency: post mode replay" do
    setup ctx, do: origin_with_review(ctx, :post)

    test "duplicate null candidate after phase 1 → idempotent 200", ctx do
      {_revoke, _post} = phase1_via_ingest!(ctx, :post)

      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)
      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)
      assert conn.status == 200

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "replayed signature update after completion fails", ctx do
      {revoke, _post} = phase1_via_ingest!(ctx, :post)
      sign_mutation = build_right_sign_mutation(revoke, ctx.author, :revoke)

      assert post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey).status ==
               200

      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)
      refute conn.status == 200
    end
  end

  describe "idempotency: pre mode replay" do
    setup ctx, do: origin_with_review(ctx, :pre)

    test "replayed signature update after completion fails", ctx do
      {revoke, post} = phase1_via_ingest!(ctx, :pre)

      post_sign = build_right_sign_mutation(post, ctx.author, :post)
      revoke_sign = build_right_sign_mutation(revoke, ctx.author, :revoke)

      assert post_ingest(ctx.conn, %{"mutations" => [post_sign]}, ctx.author.sign_skey).status ==
               200

      assert post_ingest(ctx.conn, %{"mutations" => [revoke_sign]}, ctx.author.sign_skey).status ==
               200

      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [post_sign]}, ctx.author.sign_skey)
      refute conn.status == 200
    end
  end

  # --- Batch: multiple mutations in one /ingest call ---

  describe "batch: none mode candidates in single request" do
    setup ctx, do: origin_with_review(ctx, :none)

    test "password + null in single request → auto-promotes", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end
  end

  describe "batch: post mode candidates in single request" do
    setup ctx, do: origin_with_review(ctx, :post)

    test "password + null in single request → creates revoke right candidate", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
    end

    test "null + password (reverse order) in single request → still promotes", ctx do
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [null_mutation, pwd_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end
  end

  describe "batch: pre mode candidates in single request" do
    setup ctx, do: origin_with_review(ctx, :pre)

    test "password + null in single request → creates both right candidates", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "both signature updates in single request → completes promotion", ctx do
      {revoke, post} = phase1_via_ingest!(ctx, :pre)

      post_sign = build_right_sign_mutation(post, ctx.author, :post)
      revoke_sign = build_right_sign_mutation(revoke, ctx.author, :revoke)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [post_sign, revoke_sign]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end
  end
end

defmodule Chat.Data.ReviewModerationPreTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewModerationFixtures

  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData

  setup :review_parties

  setup ctx do
    {:ok, review: moderated_review(ctx, :pre)}
  end

  describe "pre-moderation: two-phase handshake" do
    test "phase 1: creates both right candidates, returns shared_secrets", ctx do
      secrets = promote_phase1(ctx)

      assert Map.has_key?(secrets, :post_shared_secret)
      assert Map.has_key?(secrets, :revoke_shared_secret)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil

      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "phase 1: author can verify both wrappings", ctx do
      secrets = promote_phase1(ctx)

      post_rc = RightCandidateData.get_post_candidate(ctx.review.review_hash)
      post_row = unwrap_with_secret(post_rc, secrets.post_shared_secret)
      assert post_row["password_b64"] != nil

      revoke_rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      revoke_row = unwrap_with_secret(revoke_rc, secrets.revoke_shared_secret)
      assert revoke_row["password_b64"] == nil
    end

    test "phase 2: after author signs both, promotes rights (no public password)", ctx do
      promote_phase1(ctx)

      complete_promotion!(ctx, [:post, :revoke])

      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert CandidateData.get_candidates_for_review(ctx.review.review_hash) == []
    end

    test "phase 2: fails if only post right signed", ctx do
      promote_phase1(ctx)

      sign_right_candidate(:post, ctx.review.review_hash, ctx.author)

      assert {:error, "revoke right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "phase 2: fails if only revoke right signed", ctx do
      promote_phase1(ctx)

      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)

      assert {:error, "post right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "origin identity approves via post_right → review visible", ctx do
      promote_phase1(ctx)
      complete_promotion!(ctx, [:post, :revoke])

      post_right = PostRightData.get_post_right(ctx.review.review_hash)
      row = unwrap_right(post_right, ctx.origin_identity)
      assert row["password_b64"] != nil

      publish_password_row(row)

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 != nil
    end

    test "origin identity revokes after approval → review hidden", ctx do
      promote_phase1(ctx)
      complete_promotion!(ctx, [:post, :revoke])

      post_right = PostRightData.get_post_right(ctx.review.review_hash)
      publish_password_row(unwrap_right(post_right, ctx.origin_identity))

      revoke_right = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      assert null_row["password_b64"] == nil

      publish_password_row(null_row)

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert latest.password_b64 == nil
    end

    test "fails without null candidate", ctx do
      pwd_candidate = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)

      assert {:error, "null candidate required for pre mode"} =
               Promotion.promote_candidate(pwd_candidate)
    end
  end

  describe "right candidate garbage collection" do
    test "delete_stale_candidates removes old unsigned candidates", ctx do
      promote_phase1(ctx)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil

      old_ts = RightCandidateData.get_post_candidate(ctx.review.review_hash).owner_timestamp
      review2 = promote_newer_review(ctx, old_ts)

      assert RightCandidateData.get_post_candidate(review2.review_hash) != nil

      RightCandidateData.delete_stale_candidates(50)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_post_candidate(review2.review_hash) != nil
    end
  end

  defp promote_newer_review(ctx, old_ts) do
    review2 = insert_review(ctx.author, ctx.origin_hash)

    pwd2 =
      build_candidate(ctx.author, review2, ctx.origin_hash, review2.review_password,
        timestamp: old_ts + 100
      )

    _null2 = build_candidate(ctx.author, review2, ctx.origin_hash, nil, timestamp: old_ts + 101)
    {:ok, _} = Promotion.promote_candidate(pwd2)
    review2
  end
end

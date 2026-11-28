defmodule Chat.Data.ReviewModerationTest do
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

  # --- No moderation: single-phase auto-promote ---

  describe "no moderation: auto-promotes" do
    setup ctx do
      {:ok, review: moderated_review(ctx, :none)}
    end

    test "password candidate is auto-promoted to review_public_passwords", ctx do
      candidate = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)

      {:ok, _} = Promotion.promote_candidate(candidate)

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 == candidate.password_b64
    end

    test "complete_promotion returns error for :none mode", ctx do
      assert {:error, "complete_promotion not applicable for :none mode"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end
  end

  # --- Post-moderation: two-phase handshake ---

  describe "post-moderation: two-phase handshake" do
    setup ctx do
      {:ok, review: moderated_review(ctx, :post)}
    end

    test "phase 1: creates revoke right candidate, returns shared_secret", ctx do
      secrets = promote_phase1(ctx)

      assert Map.has_key?(secrets, :revoke_shared_secret)
      assert is_binary(secrets.revoke_shared_secret)

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil

      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "phase 1: author can verify wrapping with shared_secret", ctx do
      secrets = promote_phase1(ctx)

      rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      row = unwrap_with_secret(rc, secrets.revoke_shared_secret)

      assert row["password_b64"] == nil
      assert row["review_hash"] == to_string(ctx.review.review_hash)
    end

    test "phase 2: after author signs, promotes password + revoke right", ctx do
      promote_phase1(ctx)

      complete_promotion!(ctx, [:revoke])

      revoke = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      assert revoke != nil
      assert revoke.sign_b64 != nil

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 != nil

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert CandidateData.get_candidates_for_review(ctx.review.review_hash) == []
    end

    test "phase 2: fails if revoke right not signed", ctx do
      promote_phase1(ctx)

      assert {:error, "revoke right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "origin identity can revoke after promotion", ctx do
      promote_phase1(ctx)
      complete_promotion!(ctx, [:revoke])

      revoke_right = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      assert null_row["password_b64"] == nil

      publish_password_row(null_row)

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert latest.password_b64 == nil
    end
  end
end

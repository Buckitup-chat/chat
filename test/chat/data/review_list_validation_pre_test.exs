defmodule Chat.Data.ReviewListValidationPreTest do
  @moduledoc "Pre-moderation part of the review_list ingest matrix (see `ReviewListValidationTest`)."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewModerationFixtures

  alias Chat.Data.ReviewList.Validation

  setup :review_parties

  describe "pre mode" do
    setup ctx do
      review = moderated_review(ctx, :pre)
      post = insert_post_right(ctx.author, review, ctx.origin_hash)
      revoke = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, post_sh: post.sign_hash, revoke_sh: revoke.sign_hash}
    end

    test "accepts post + revoke right proofs with null password", ctx do
      cs =
        validate_review_list_insert(ctx,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects a dangling password proof (references no promoted row)", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: random_password_sign_hash(),
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
    end

    test "accepts a promoted password proof after approval (fill-in, docs §439)", ctx do
      pwd_sh = insert_public_password(ctx.author, ctx.review, ctx.origin_hash).sign_hash

      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: pwd_sh,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "accepts an update that fills the password proof after approval", ctx do
      existing =
        build_review_list(ctx.author, ctx.review,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh,
          ts: 1000
        )

      pwd_sh = insert_public_password(ctx.author, ctx.review, ctx.origin_hash).sign_hash

      update =
        build_review_list(ctx.author, ctx.review,
          review_password_sign_hash: pwd_sh,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh,
          ts: 2000
        )

      cs = Validation.validate_review_list_update(existing, update)

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when post-right proof is missing", ctx do
      cs =
        validate_review_list_insert(ctx,
          post_right_sign_hash: nil,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end

    test "rejects a forged post-right proof (wrong sign_hash)", ctx do
      cs =
        validate_review_list_insert(ctx,
          post_right_sign_hash: random_post_sign_hash(),
          revoke_right_sign_hash: ctx.revoke_sh
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end
  end
end

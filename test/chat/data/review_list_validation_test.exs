defmodule Chat.Data.ReviewListValidationTest do
  @moduledoc """
  Moderation-bypass-prevention matrix for review_list ingest.

  Exercises `Chat.Data.ReviewList.Validation` directly across the three
  moderation modes and every proof-field state (null / valid / forged),
  mirroring the "Server validation on review_list ingest" and
  "Moderation proof requirements by mode" sections of
  docs/pq/reqs/reviews/pq_review_contacts.done.md.

  Pre mode lives in `ReviewListValidationPreTest`, the update path and signature
  checks in `ReviewListValidationUpdateTest`.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewModerationFixtures

  alias Chat.Data.User

  setup :review_parties

  # --- none mode ---

  describe "none mode" do
    setup ctx do
      review = moderated_review(ctx, :none)
      pwd = insert_public_password(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd.sign_hash}
    end

    test "accepts a row proving promotion", ctx do
      cs = validate_review_list_insert(ctx, review_password_sign_hash: ctx.pwd_sh)
      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when password proof is missing", ctx do
      cs = validate_review_list_insert(ctx, review_password_sign_hash: nil)
      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
    end

    test "rejects a forged password proof (no matching row)", ctx do
      cs =
        validate_review_list_insert(ctx, review_password_sign_hash: random_password_sign_hash())

      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
    end

    test "rejects when post_right proof is present (must be null)", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          post_right_sign_hash: random_post_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end

    test "rejects when revoke_right proof is present (must be null)", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: random_revoke_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects a row whose origin_hash is not the review's origin", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          origin_hash: unrelated_origin_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :origin_hash)
    end
  end

  defp unrelated_origin_hash do
    "OtherShop"
    |> User.generate_pq_identity()
    |> User.extract_pq_card()
    |> Map.fetch!(:user_hash)
  end

  # --- post mode ---

  describe "post mode" do
    setup ctx do
      review = moderated_review(ctx, :post)
      pwd = insert_public_password(ctx.author, review, ctx.origin_hash)
      revoke = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd.sign_hash, revoke_sh: revoke.sign_hash}
    end

    test "accepts password + revoke-right proofs", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when revoke-right proof is missing", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: nil
        )

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects a forged revoke-right proof (wrong sign_hash)", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: random_revoke_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects when post_right proof is present (must be null)", ctx do
      cs =
        validate_review_list_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: ctx.revoke_sh,
          post_right_sign_hash: random_post_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end
  end

  # --- moderation bypass: dangling references ---

  describe "moderation bypass prevention" do
    test "rejects a review_list row for a review that does not exist", ctx do
      phantom = %{review_hash: random_review_hash(), origin_hash: ctx.origin_hash}

      cs =
        ctx
        |> Map.put(:review, phantom)
        |> validate_review_list_insert(review_password_sign_hash: random_password_sign_hash())

      refute cs.valid?
      assert error_on?(cs, :review_hash)
    end
  end
end

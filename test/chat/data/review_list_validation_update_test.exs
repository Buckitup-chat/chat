defmodule Chat.Data.ReviewListValidationUpdateTest do
  @moduledoc "review_list update path and signature / timestamp integrity (see `ReviewListValidationTest`)."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewModerationFixtures

  alias Chat.Data.ReviewList.Validation

  setup :review_parties

  # --- update path must re-check the proof (docs §401) ---

  describe "update path re-validates moderation proof" do
    setup ctx do
      review = moderated_review(ctx, :none)
      pwd_sh = insert_public_password(ctx.author, review, ctx.origin_hash).sign_hash

      existing =
        build_review_list(ctx.author, review, review_password_sign_hash: pwd_sh, ts: 1000)

      {:ok, review: review, pwd_sh: pwd_sh, existing: existing}
    end

    test "rejects an update that forges a proof field", ctx do
      update =
        build_review_list(ctx.author, ctx.review,
          review_password_sign_hash: ctx.pwd_sh,
          post_right_sign_hash: random_post_sign_hash(),
          ts: 2000
        )

      cs = Validation.validate_review_list_update(ctx.existing, update)

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end

    test "accepts an update that keeps a valid proof", ctx do
      update =
        build_review_list(ctx.author, ctx.review, review_password_sign_hash: ctx.pwd_sh, ts: 2000)

      cs = Validation.validate_review_list_update(ctx.existing, update)

      assert cs.valid?, inspect(cs.errors)
    end
  end

  # --- signature + timestamp integrity ---

  describe "signature and timestamp integrity" do
    setup ctx do
      review = moderated_review(ctx, :none)
      pwd_sh = insert_public_password(ctx.author, review, ctx.origin_hash).sign_hash
      {:ok, review: review, pwd_sh: pwd_sh}
    end

    test "rejects a row with a forged signature", ctx do
      rl =
        ctx.author
        |> build_review_list(ctx.review, review_password_sign_hash: ctx.pwd_sh)
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

      cs = Validation.validate_review_list_insert(rl)

      refute cs.valid?
      assert error_on?(cs, :sign_b64)
    end

    test "rejects a stale update (timestamp not newer than existing)", ctx do
      existing =
        build_review_list(ctx.author, ctx.review, review_password_sign_hash: ctx.pwd_sh, ts: 2000)

      update =
        build_review_list(ctx.author, ctx.review, review_password_sign_hash: ctx.pwd_sh, ts: 1000)

      cs = Validation.validate_review_list_update(existing, update)

      refute cs.valid?
    end
  end
end

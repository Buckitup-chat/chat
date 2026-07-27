defmodule Chat.Data.ReviewListValidationTest do
  @moduledoc """
  Moderation-bypass-prevention matrix for review_list ingest.

  Exercises `Chat.Data.ReviewList.Validation` directly across the three
  moderation modes and every proof-field state (null / valid / forged),
  mirroring the "Server validation on review_list ingest" and
  "Moderation proof requirements by mode" sections of
  docs/proposal/reviews.md.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewList.Validation
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.User

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    author = User.generate_pq_identity("Author")
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)

    {:ok,
     author: author,
     owner: owner,
     origin_identity: origin_identity,
     author_hash: author_card.user_hash,
     origin_hash: origin_card.user_hash}
  end

  # --- none mode ---

  describe "none mode" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
      pwd = insert_public_password(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd.sign_hash}
    end

    test "accepts a row proving promotion", ctx do
      cs = validate_insert(ctx, review_password_sign_hash: ctx.pwd_sh)
      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when password proof is missing", ctx do
      cs = validate_insert(ctx, review_password_sign_hash: nil)
      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
    end

    test "rejects a forged password proof (no matching row)", ctx do
      cs = validate_insert(ctx, review_password_sign_hash: random_password_sign_hash())
      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
    end

    test "rejects when post_right proof is present (must be null)", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          post_right_sign_hash: random_post_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end

    test "rejects when revoke_right proof is present (must be null)", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: random_revoke_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects a row whose origin_hash is not the review's origin", ctx do
      cs =
        validate_insert(ctx,
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
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      pwd = insert_public_password(ctx.author, review, ctx.origin_hash)
      revoke = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd.sign_hash, revoke_sh: revoke.sign_hash}
    end

    test "accepts password + revoke-right proofs", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when revoke-right proof is missing", ctx do
      cs =
        validate_insert(ctx, review_password_sign_hash: ctx.pwd_sh, revoke_right_sign_hash: nil)

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects a forged revoke-right proof (wrong sign_hash)", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: random_revoke_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :revoke_right_sign_hash)
    end

    test "rejects when post_right proof is present (must be null)", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: ctx.pwd_sh,
          revoke_right_sign_hash: ctx.revoke_sh,
          post_right_sign_hash: random_post_sign_hash()
        )

      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end
  end

  # --- pre mode ---

  describe "pre mode" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      post = insert_post_right(ctx.author, review, ctx.origin_hash)
      revoke = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, post_sh: post.sign_hash, revoke_sh: revoke.sign_hash}
    end

    test "accepts post + revoke right proofs with null password", ctx do
      cs =
        validate_insert(ctx,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects a dangling password proof (references no promoted row)", ctx do
      cs =
        validate_insert(ctx,
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
        validate_insert(ctx,
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
      cs = validate_insert(ctx, post_right_sign_hash: nil, revoke_right_sign_hash: ctx.revoke_sh)
      refute cs.valid?
      assert error_on?(cs, :post_right_sign_hash)
    end

    test "rejects a forged post-right proof (wrong sign_hash)", ctx do
      cs =
        validate_insert(ctx,
          post_right_sign_hash: random_post_sign_hash(),
          revoke_right_sign_hash: ctx.revoke_sh
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
        |> validate_insert(review_password_sign_hash: random_password_sign_hash())

      refute cs.valid?
      assert error_on?(cs, :review_hash)
    end
  end

  # --- update path must re-check the proof (docs §401) ---

  describe "update path re-validates moderation proof" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
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
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
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

  # --- Helpers ---

  defp validate_insert(ctx, row_opts) do
    ctx.author
    |> build_review_list(ctx.review, row_opts)
    |> Validation.validate_review_list_insert()
  end

  defp build_review_list(author, review, opts) do
    rl = %ReviewList{
      user_hash: User.extract_pq_card(author).user_hash,
      review_hash: review.review_hash,
      origin_hash: Keyword.get(opts, :origin_hash, review.origin_hash),
      password_b64: :crypto.strong_rand_bytes(32),
      review_password_sign_hash: Keyword.get(opts, :review_password_sign_hash),
      post_right_sign_hash: Keyword.get(opts, :post_right_sign_hash),
      revoke_right_sign_hash: Keyword.get(opts, :revoke_right_sign_hash),
      deleted_flag: false,
      owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond))
    }

    sign_with_hash(rl, author.sign_skey, &ReviewListSignHash.from_binary/1)
  end

  defp error_on?(changeset, field), do: Keyword.has_key?(changeset.errors, field)
end

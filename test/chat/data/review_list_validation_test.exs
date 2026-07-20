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

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewList.Validation
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

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
      pwd_sh = insert_public_password(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd_sh}
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
  end

  # --- post mode ---

  describe "post mode" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      pwd_sh = insert_public_password(ctx.author, review, ctx.origin_hash)
      revoke_sh = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, pwd_sh: pwd_sh, revoke_sh: revoke_sh}
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
      post_sh = insert_post_right(ctx.author, review, ctx.origin_hash)
      revoke_sh = insert_revoke_right(ctx.author, review, ctx.origin_hash)
      {:ok, review: review, post_sh: post_sh, revoke_sh: revoke_sh}
    end

    test "accepts post + revoke right proofs with null password", ctx do
      cs =
        validate_insert(ctx,
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects when password proof is present (must be null until approval)", ctx do
      cs =
        validate_insert(ctx,
          review_password_sign_hash: random_password_sign_hash(),
          post_right_sign_hash: ctx.post_sh,
          revoke_right_sign_hash: ctx.revoke_sh
        )

      refute cs.valid?
      assert error_on?(cs, :review_password_sign_hash)
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
      pwd_sh = insert_public_password(ctx.author, review, ctx.origin_hash)

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

  # --- Helpers ---

  defp validate_insert(ctx, proof_opts) do
    ctx.author
    |> build_review_list(ctx.review, proof_opts)
    |> Validation.validate_review_list_insert()
  end

  defp build_review_list(author, review, opts) do
    rl = %ReviewList{
      user_hash: User.extract_pq_card(author).user_hash,
      review_hash: review.review_hash,
      password_b64: :crypto.strong_rand_bytes(32),
      review_password_sign_hash: Keyword.get(opts, :review_password_sign_hash),
      post_right_sign_hash: Keyword.get(opts, :post_right_sign_hash),
      revoke_right_sign_hash: Keyword.get(opts, :revoke_right_sign_hash),
      deleted_flag: false,
      owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond))
    }

    sign_with_hash(rl, author.sign_skey, &ReviewListSignHash.from_binary/1)
  end

  defp insert_public_password(author, review, origin_hash) do
    author_hash = User.extract_pq_card(author).user_hash

    rp = %ReviewPublicPassword{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      password_b64: :crypto.strong_rand_bytes(32),
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(rp, author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

    {:ok, _} =
      %ReviewPublicPassword{}
      |> ReviewPublicPassword.create_changeset(Map.from_struct(signed))
      |> PublicPasswordData.upsert_review_public_password()

    signed.sign_hash
  end

  defp insert_post_right(author, review, origin_hash) do
    author
    |> build_right(review, origin_hash, ReviewPostRight, &ReviewPostRightSignHash.from_binary/1)
    |> then(fn signed ->
      {:ok, _} =
        %ReviewPostRight{}
        |> ReviewPostRight.create_changeset(Map.from_struct(signed))
        |> PostRightData.upsert_post_right()

      signed.sign_hash
    end)
  end

  defp insert_revoke_right(author, review, origin_hash) do
    author
    |> build_right(
      review,
      origin_hash,
      ReviewRevokeRight,
      &ReviewRevokeRightSignHash.from_binary/1
    )
    |> then(fn signed ->
      {:ok, _} =
        %ReviewRevokeRight{}
        |> ReviewRevokeRight.create_changeset(Map.from_struct(signed))
        |> RevokeRightData.upsert_revoke_right()

      signed.sign_hash
    end)
  end

  defp build_right(author, review, origin_hash, schema, hash_fn) do
    right =
      struct(schema, %{
        review_hash: review.review_hash,
        origin_hash: origin_hash,
        author_hash: User.extract_pq_card(author).user_hash,
        kem_ciphertext_b64: :crypto.strong_rand_bytes(32),
        wrapped_row_b64: :crypto.strong_rand_bytes(64),
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      })

    sign_with_hash(right, author.sign_skey, hash_fn)
  end

  defp insert_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp insert_origin(origin_identity, owner, moderation_mode) do
    origin_card = User.extract_pq_card(origin_identity)
    owner_card = User.extract_pq_card(owner)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    origin = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner_card.user_hash,
      owner_cert: owner_cert,
      name: "Test Origin",
      moderation_mode: moderation_mode,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(origin, origin_identity.sign_skey, &OriginSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:origin, :insert, signed)
    signed
  end

  defp insert_review(author, origin_hash) do
    review_hash = random_review_hash()
    author_hash = User.extract_pq_card(author).user_hash

    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:review, :insert, signed)
    signed
  end

  defp random_review_hash, do: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()

  defp random_password_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewPasswordSignHash.from_binary()

  defp random_post_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewPostRightSignHash.from_binary()

  defp random_revoke_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewRevokeRightSignHash.from_binary()

  defp error_on?(changeset, field), do: Keyword.has_key?(changeset.errors, field)

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp sign_with_hash(struct, sign_skey, hash_fn) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_fn.()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end
end

defmodule Chat.Test.ReviewModerationFixtures do
  @moduledoc """
  Review moderation setups shared by the `review_moderation_*` and `review_list_validation_*`
  tests: the author / owner / origin parties, a review under a given moderation mode, the
  two-phase promotion handshake and signed `review_list` rows.
  """

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewList.Validation
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.User

  @doc """
  Setup: clears deferred records, inserts signed user cards for an author, an owner and an
  origin, and returns `author`, `owner`, `origin_identity`, `author_hash` and `origin_hash`.
  """
  def review_parties(_ctx) do
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

  @doc "Inserts the origin with `moderation_mode` and a review by the author on it."
  def moderated_review(ctx, moderation_mode) do
    insert_origin(ctx.origin_identity, ctx.owner, moderation_mode)
    insert_review(ctx.author, ctx.origin_hash)
  end

  @doc """
  Phase 1 of the handshake: inserts the password and null candidates for `ctx.review`,
  promotes the password one and returns the shared secrets.
  """
  def promote_phase1(ctx) do
    password = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)
    _null = insert_null_candidate(ctx.author, ctx.review, ctx.origin_hash)
    {:ok, secrets} = Promotion.promote_candidate(password)
    secrets
  end

  @doc "Phase 2: the author signs the given right candidates, then promotion completes."
  def complete_promotion!(ctx, rights) do
    Enum.each(rights, &sign_right_candidate(&1, ctx.review.review_hash, ctx.author))
    {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)
  end

  @doc "Validates a `review_list` insert by the author for `ctx.review`; returns the changeset."
  def validate_review_list_insert(ctx, row_opts) do
    ctx.author
    |> build_review_list(ctx.review, row_opts)
    |> Validation.validate_review_list_insert()
  end

  @doc """
  Signed `review_list` row. Options: proof sign hashes (`review_password_sign_hash`,
  `post_right_sign_hash`, `revoke_right_sign_hash`), `origin_hash`, `ts`.
  """
  def build_review_list(author, review, opts) do
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

  @doc "Whether the changeset has an error on `field`."
  def error_on?(changeset, field), do: Keyword.has_key?(changeset.errors, field)
end

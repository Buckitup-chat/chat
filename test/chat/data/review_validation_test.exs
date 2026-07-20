defmodule Chat.Data.ReviewValidationTest do
  @moduledoc """
  Signature + origin-binding validation for review rows.

  `Chat.Data.Review.Validation` must verify the author's signature over the
  review row, reject a review pointing at a non-existent origin, and reject a
  stale update whose timestamp is not newer than the existing row (LWW).
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.ReviewHash
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

    insert_origin(origin_identity, owner)

    {:ok, author: author, author_hash: author_card.user_hash, origin_hash: origin_card.user_hash}
  end

  test "accepts a signed review for an existing origin", ctx do
    cs =
      ctx.author
      |> build_review(ctx.origin_hash)
      |> Validation.validate_review_insert()

    assert cs.valid?, inspect(cs.errors)
  end

  test "rejects a review with a forged signature", ctx do
    forged =
      ctx.author
      |> build_review(ctx.origin_hash)
      |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

    cs = Validation.validate_review_insert(forged)

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :sign_b64)
  end

  test "rejects a review whose origin does not exist", ctx do
    phantom_origin = User.extract_pq_card(User.generate_pq_identity("Ghost")).user_hash

    cs =
      ctx.author
      |> build_review(phantom_origin)
      |> Validation.validate_review_insert()

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :origin_hash)
  end

  test "rejects a stale review update (timestamp not newer than existing)", ctx do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    existing = build_review(ctx.author, ctx.origin_hash, review_hash: review_hash, ts: 2000)
    update = build_review(ctx.author, ctx.origin_hash, review_hash: review_hash, ts: 1000)

    cs = Validation.validate_review_update(existing, update)

    refute cs.valid?
  end

  # --- Helpers ---

  defp build_review(author, origin_hash, opts \\ []) do
    review = %Review{
      review_hash: Keyword.get(opts, :review_hash) || random_review_hash(),
      origin_hash: origin_hash,
      author_hash: User.extract_pq_card(author).user_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond))
    }

    sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp random_review_hash, do: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()

  defp insert_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp insert_origin(origin_identity, owner) do
    origin_card = User.extract_pq_card(origin_identity)
    owner_card = User.extract_pq_card(owner)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    origin = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner_card.user_hash,
      owner_cert: owner_cert,
      name: "Test Origin",
      moderation_mode: :none,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(origin, origin_identity.sign_skey, &OriginSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:origin, :insert, signed)
    signed
  end

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

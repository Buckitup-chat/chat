defmodule Chat.Data.ReviewPublicPasswordValidationTest do
  @moduledoc """
  Peer-sync validation for review_public_passwords rows.

  A review_public_passwords row is the "proof of promotion" that review_list
  relies on, so `Chat.Data.ReviewPublicPassword.Validation` must bind each row
  to the review it references (author + origin) and reject rows whose signature
  does not verify.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewPublicPassword.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    author = User.generate_pq_identity("Author")
    attacker = User.generate_pq_identity("Attacker")
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _attacker_card = insert_user_card(attacker)
    _owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner)
    review = insert_review(author, origin_card.user_hash)

    {:ok,
     author: author,
     attacker: attacker,
     origin_hash: origin_card.user_hash,
     author_hash: author_card.user_hash,
     review: review}
  end

  test "accepts the review author's own promotion row", ctx do
    cs =
      ctx.author
      |> build_password(ctx.review, ctx.author_hash, ctx.origin_hash)
      |> Validation.validate_review_public_password_insert()

    assert cs.valid?, inspect(cs.errors)
  end

  test "rejects a row whose author does not match the review", ctx do
    attacker_hash = User.extract_pq_card(ctx.attacker).user_hash

    cs =
      ctx.attacker
      |> build_password(ctx.review, attacker_hash, ctx.origin_hash)
      |> Validation.validate_review_public_password_insert()

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :author_hash)
  end

  test "rejects a row whose origin does not match the review", ctx do
    other_origin = User.extract_pq_card(User.generate_pq_identity("OtherShop")).user_hash

    cs =
      ctx.author
      |> build_password(ctx.review, ctx.author_hash, other_origin)
      |> Validation.validate_review_public_password_insert()

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :origin_hash)
  end

  test "rejects a row for a review that does not exist", ctx do
    phantom = %{
      ctx.review
      | review_hash: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    }

    cs =
      ctx.author
      |> build_password(phantom, ctx.author_hash, ctx.origin_hash)
      |> Validation.validate_review_public_password_insert()

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :review_hash)
  end

  test "rejects a row with a tampered signature", ctx do
    tampered =
      ctx.author
      |> build_password(ctx.review, ctx.author_hash, ctx.origin_hash)
      |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

    cs = Validation.validate_review_public_password_insert(tampered)

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :sign_b64)
  end

  describe "visibility is last-write-wins by owner_timestamp" do
    test "a later null (revoke) row supersedes an earlier password row", ctx do
      persist(build_password_at(ctx, ctx.author_hash, :crypto.strong_rand_bytes(32), 1000))
      persist(build_password_at(ctx, ctx.author_hash, nil, 2000))

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)

      assert latest.owner_timestamp == 2000
      assert latest.password_b64 == nil
    end

    test "a stale (older) row does not become the current version", ctx do
      persist(build_password_at(ctx, ctx.author_hash, :crypto.strong_rand_bytes(32), 2000))
      persist(build_password_at(ctx, ctx.author_hash, nil, 1000))

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)

      assert latest.owner_timestamp == 2000
      refute is_nil(latest.password_b64)
    end
  end

  # --- Helpers ---

  defp build_password_at(ctx, author_hash, password_b64, owner_timestamp) do
    rp = %ReviewPublicPassword{
      review_hash: ctx.review.review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: owner_timestamp
    }

    sign_b64 = rp |> Integrity.signature_payload() |> EnigmaPq.sign(ctx.author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()
    %{rp | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp persist(rp) do
    {:ok, _} =
      %ReviewPublicPassword{}
      |> ReviewPublicPassword.create_changeset(Map.from_struct(rp))
      |> PublicPasswordData.upsert_review_public_password()
  end

  defp build_password(signer, review, author_hash, origin_hash) do
    rp = %ReviewPublicPassword{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      password_b64: :crypto.strong_rand_bytes(32),
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = rp |> Integrity.signature_payload() |> EnigmaPq.sign(signer.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()
    %{rp | sign_b64: sign_b64, sign_hash: sign_hash}
  end

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

  defp insert_review(author, origin_hash) do
    review = %Review{
      review_hash: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary(),
      origin_hash: origin_hash,
      author_hash: User.extract_pq_card(author).user_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:review, :insert, signed)
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

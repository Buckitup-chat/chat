defmodule Chat.Data.ReviewVersioningTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Ecto.Query
  import Chat.Test.ReviewFixtures

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewVersion
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.Repo
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
     author_hash: author_card.user_hash,
     origin_hash: origin_card.user_hash,
     origin_identity: origin_identity,
     owner: owner}
  end

  describe "review versioning" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner)
      :ok
    end

    test "archives old version when updating with newer timestamp", ctx do
      review = insert_review(ctx.author, ctx.origin_hash)
      v1_sign_hash = review.sign_hash
      v2 = build_signed_review_update(ctx.author, review, review.owner_timestamp + 10)

      {:ok, _} = ReviewData.update_review_with_versioning(review, v2)

      tip = ReviewData.get_review(review.review_hash)
      assert tip.sign_hash == v2.sign_hash
      assert tip.parent_sign_hash == v1_sign_hash

      archived = get_archived_version(review.review_hash)
      assert archived.sign_hash == v1_sign_hash
      assert archived.content_b64 == review.content_b64
    end

    test "archives incoming old version when it has older timestamp", ctx do
      review = insert_review(ctx.author, ctx.origin_hash, ts: 2000)
      old_version = build_signed_review_update(ctx.author, review, 1000)

      {:ok, _} = ReviewData.update_review_with_versioning(review, old_version)

      tip = ReviewData.get_review(review.review_hash)
      assert tip.sign_hash == review.sign_hash

      archived = get_archived_version(review.review_hash)
      assert archived.sign_hash == old_version.sign_hash
    end

    test "insert_review_with_conflict archives existing when new is newer", ctx do
      review = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      v1_sign_hash = review.sign_hash
      v2 = build_signed_review(ctx.author, ctx.origin_hash, review.review_hash, 2000)

      {:ok, _} = ReviewData.insert_review_with_conflict(review, v2)

      tip = ReviewData.get_review(review.review_hash)
      assert tip.sign_hash == v2.sign_hash
      assert tip.parent_sign_hash == v1_sign_hash

      archived = get_archived_version(review.review_hash)
      assert archived.sign_hash == v1_sign_hash
    end

    test "insert_review_with_conflict archives incoming when it's older", ctx do
      review = insert_review(ctx.author, ctx.origin_hash, ts: 2000)
      old = build_signed_review(ctx.author, ctx.origin_hash, review.review_hash, 1000)

      {:ok, _} = ReviewData.insert_review_with_conflict(review, old)

      tip = ReviewData.get_review(review.review_hash)
      assert tip.sign_hash == review.sign_hash

      archived = get_archived_version(review.review_hash)
      assert archived.sign_hash == old.sign_hash
    end

    test "version chain is tamper-evident through parent_sign_hash", ctx do
      v1 = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      v2 = build_signed_review_update(ctx.author, v1, 2000)
      {:ok, _} = ReviewData.update_review_with_versioning(v1, v2)

      updated_v1 = ReviewData.get_review(v1.review_hash)
      v3 = build_signed_review_update(ctx.author, updated_v1, 3000)
      {:ok, _} = ReviewData.update_review_with_versioning(updated_v1, v3)

      tip = ReviewData.get_review(v1.review_hash)
      assert tip.sign_hash == v3.sign_hash

      [archived_v1, archived_v2] = get_archived_versions_ordered(v1.review_hash)

      assert archived_v1.sign_hash == v1.sign_hash
      assert archived_v1.parent_sign_hash == nil

      assert archived_v2.sign_hash == v2.sign_hash
      assert archived_v2.parent_sign_hash == v1.sign_hash

      assert tip.parent_sign_hash == v2.sign_hash
    end

    test "idempotent archive insert does not fail", ctx do
      review = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      v2 = build_signed_review_update(ctx.author, review, 2000)
      {:ok, _} = ReviewData.update_review_with_versioning(review, v2)

      changeset = Chat.Data.Review.Versioning.archive_changeset(review)

      assert {:ok, _} =
               Repo.insert(changeset,
                 on_conflict: :nothing,
                 conflict_target: [:review_hash, :sign_hash],
                 allow_stale: true
               )
    end
  end

  describe "pre-mode lock detection" do
    test "rejects edit when pre-mode and review_public_passwords exists", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      existing = ReviewData.get_review(review.review_hash)
      _pp = insert_public_password(ctx.author, review, ctx.origin_hash)

      changeset = validate_update_with_versioning(ctx.author, existing)

      refute changeset.valid?
      {msg, _} = Keyword.fetch!(changeset.errors, :review_hash)
      assert msg == "editing locked after pre-moderation"
    end

    test "allows edit when pre-mode without public password (pending)", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      existing = ReviewData.get_review(review.review_hash)

      changeset = validate_update_with_versioning(ctx.author, existing)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "allows edit in none mode even with public password", ctx do
      changeset = validate_moderated_edit(ctx, :none, with_password: true)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "allows edit in post mode even with public password", ctx do
      changeset = validate_moderated_edit(ctx, :post, with_password: true)
      assert changeset.valid?, inspect(changeset.errors)
    end
  end

  # Helpers

  defp validate_moderated_edit(ctx, mode, opts) do
    insert_origin(ctx.origin_identity, ctx.owner, mode)
    review = insert_review(ctx.author, ctx.origin_hash)
    existing = ReviewData.get_review(review.review_hash)

    if opts[:with_password],
      do: insert_public_password(ctx.author, review, ctx.origin_hash)

    validate_update_with_versioning(ctx.author, existing)
  end

  defp validate_update_with_versioning(author, existing) do
    v2 = build_signed_review_update(author, existing, existing.owner_timestamp + 10)

    Validation.review_validate_with_versioning(
      existing,
      update_changes_from(v2),
      :update
    )
  end

  defp get_archived_version(review_hash) do
    Repo.one(from(rv in ReviewVersion, where: rv.review_hash == ^review_hash))
  end

  defp get_archived_versions_ordered(review_hash) do
    ReviewVersion
    |> where([rv], rv.review_hash == ^review_hash)
    |> order_by([rv], asc: rv.owner_timestamp)
    |> Repo.all()
  end

  defp build_signed_review(author, origin_hash, review_hash, ts) do
    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: User.extract_pq_card(author).user_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }

    sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp build_signed_review_update(author, existing_review, new_ts) do
    review = %Review{
      review_hash: existing_review.review_hash,
      origin_hash: existing_review.origin_hash,
      author_hash: existing_review.author_hash,
      content_b64: EnigmaPq.aes_gcm_encrypt("Updated review!", :crypto.strong_rand_bytes(32)),
      deleted_flag: false,
      parent_sign_hash: existing_review.sign_hash,
      owner_timestamp: new_ts
    }

    sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp update_changes_from(review) do
    %{
      "content_b64" => review.content_b64,
      "deleted_flag" => review.deleted_flag,
      "parent_sign_hash" => review.parent_sign_hash,
      "owner_timestamp" => review.owner_timestamp,
      "sign_b64" => review.sign_b64,
      "sign_hash" => review.sign_hash
    }
  end
end

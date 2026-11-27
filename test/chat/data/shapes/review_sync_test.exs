defmodule Chat.Data.Shapes.ReviewSyncTest do
  @moduledoc """
  Peer-sync persist of the `review` and `review_public_passwords` shapes,
  called directly (the way `ShapeWriter` does): forged rows are dropped with a
  warning, known reviews go through versioning, unknown updates are skipped.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import ExUnit.CaptureLog

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Shapes
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    author = User.generate_pq_identity("Author")
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    insert_user_card(author)
    insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)
    insert_origin(origin_identity, owner)

    {:ok, author: author, origin_hash: origin_card.user_hash}
  end

  describe "Review.sync_persist(:insert, _)" do
    test "drops a review with a forged signature", ctx do
      forged = ctx.author |> signed_review(ctx.origin_hash, 1000) |> forge()

      log =
        capture_log(fn ->
          assert {:ok, ^forged} = Shapes.Review.sync_persist(:insert, forged)
        end)

      assert log =~ "Invalid review insert signature"
      refute ReviewData.get_review(forged.review_hash)
    end

    test "versions a newer insert of an already known review", ctx do
      v1 = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      v2 = signed_review(ctx.author, ctx.origin_hash, 2000, review_hash: v1.review_hash)

      assert {:ok, _} = Shapes.Review.sync_persist(:insert, v2)

      assert %{sign_hash: tip_sign_hash, parent_sign_hash: parent} =
               ReviewData.get_review(v1.review_hash)

      assert tip_sign_hash == v2.sign_hash
      assert parent == v1.sign_hash
    end
  end

  describe "Review.sync_persist(:update, _)" do
    test "skips an update for an unknown review", ctx do
      review = signed_review(ctx.author, ctx.origin_hash, 1000)

      assert {:ok, ^review} = Shapes.Review.sync_persist(:update, review)
      refute ReviewData.get_review(review.review_hash)
    end

    test "applies a newer signed update with versioning", ctx do
      v1 = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      v2 = signed_update(ctx.author, v1, 2000)

      assert {:ok, _} = Shapes.Review.sync_persist(:update, v2)

      assert %{sign_hash: tip_sign_hash} = ReviewData.get_review(v1.review_hash)
      assert tip_sign_hash == v2.sign_hash
    end

    test "drops an update with a forged signature", ctx do
      v1 = insert_review(ctx.author, ctx.origin_hash, ts: 1000)
      forged = ctx.author |> signed_update(v1, 2000) |> forge()

      log =
        capture_log(fn ->
          assert {:ok, ^forged} = Shapes.Review.sync_persist(:update, forged)
        end)

      assert log =~ "Invalid review update signature"
      assert %{sign_hash: tip_sign_hash} = ReviewData.get_review(v1.review_hash)
      assert tip_sign_hash == v1.sign_hash
    end
  end

  describe "ReviewPublicPasswords.sync_persist/2" do
    setup ctx do
      {:ok, review: insert_review(ctx.author, ctx.origin_hash, ts: 1000)}
    end

    test "stores a signed password row", ctx do
      rp = signed_password(ctx.author, ctx.review, ctx.origin_hash)

      assert {:ok, _} = Shapes.ReviewPublicPasswords.sync_persist(:insert, rp)
      assert %{sign_hash: sign_hash} = PublicPasswordData.get_password_version(rp.review_hash)
      assert sign_hash == rp.sign_hash
    end

    test "drops a password row with a forged signature", ctx do
      forged = ctx.author |> signed_password(ctx.review, ctx.origin_hash) |> forge()

      log =
        capture_log(fn ->
          assert {:ok, ^forged} = Shapes.ReviewPublicPasswords.sync_persist(:insert, forged)
        end)

      assert log =~ "Invalid review_public_password"
      refute PublicPasswordData.get_password_version(forged.review_hash)
    end
  end

  # Helpers

  defp signed_review(author, origin_hash, ts, opts \\ []) do
    %Review{
      review_hash: Keyword.get_lazy(opts, :review_hash, &random_review_hash/0),
      origin_hash: origin_hash,
      author_hash: User.extract_pq_card(author).user_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }
    |> sign_with_hash(author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp signed_update(author, existing, ts) do
    Review
    |> struct(Map.from_struct(existing))
    |> struct(
      content_b64: :crypto.strong_rand_bytes(48),
      parent_sign_hash: existing.sign_hash,
      owner_timestamp: ts
    )
    |> sign_with_hash(author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp signed_password(author, review, origin_hash) do
    %ReviewPublicPassword{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      password_b64: :crypto.strong_rand_bytes(32),
      author_hash: User.extract_pq_card(author).user_hash,
      deleted_flag: false,
      owner_timestamp: 2000
    }
    |> sign_with_hash(author.sign_skey, &ReviewPasswordSignHash.from_binary/1)
  end

  defp forge(row), do: %{row | owner_timestamp: row.owner_timestamp + 1}
end

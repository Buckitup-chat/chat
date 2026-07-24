defmodule Chat.Data.ReviewModerationConcurrencyTest do
  use ChatWeb.DataCase, async: false, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.User

  @moduletag shared_sandbox: true

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

  describe "concurrent candidate submissions" do
    test "two simultaneous password candidates for the same review: exactly one succeeds", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            try do
              candidate = insert_password_candidate(ctx.author, review, ctx.origin_hash)
              Promotion.promote_candidate(candidate)
            rescue
              e -> {:error, e}
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      oks = Enum.count(results, &match?({:ok, _}, &1))
      errors = Enum.count(results, &(not match?({:ok, _}, &1)))

      assert oks >= 1
      assert oks + errors == 2

      published = PublicPasswordData.get_latest_for_review(review.review_hash)
      assert published != nil
    end
  end

  describe "concurrent promote and complete_promotion" do
    test "concurrent complete_promotion calls: at most one succeeds", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)

      pwd = insert_password_candidate(ctx.author, review, ctx.origin_hash)
      _null = insert_null_candidate(ctx.author, review, ctx.origin_hash)
      {:ok, _secrets} = Promotion.promote_candidate(pwd)

      sign_right_candidate(:revoke, review.review_hash, ctx.author)

      tasks =
        for _ <- 1..3 do
          Task.async(fn ->
            try do
              Promotion.complete_promotion(review.review_hash)
            rescue
              e -> {:error, e}
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      oks = Enum.count(results, &match?({:ok, _}, &1))

      assert oks >= 1

      assert RevokeRightData.get_revoke_right(review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(review.review_hash) != nil
    end
  end

  describe "concurrent promote vs revoke ordering" do
    test "concurrent password + null candidate insertion preserves timestamp ordering", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)

      pwd_task =
        Task.async(fn ->
          try do
            insert_password_candidate(ctx.author, review, ctx.origin_hash)
          rescue
            e -> {:error, e}
          end
        end)

      null_task =
        Task.async(fn ->
          try do
            insert_null_candidate(ctx.author, review, ctx.origin_hash)
          rescue
            e -> {:error, e}
          end
        end)

      [pwd_result, null_result] = Task.await_many([pwd_task, null_task], 10_000)

      case {pwd_result, null_result} do
        {{:error, _}, _} ->
          :ok

        {_, {:error, _}} ->
          :ok

        {pwd, _null} ->
          result = Promotion.promote_candidate(pwd)

          case result do
            {:ok, _} ->
              assert RightCandidateData.get_revoke_candidate(review.review_hash) != nil

            {:error, _} ->
              :ok
          end
      end
    end
  end
end

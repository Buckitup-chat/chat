defmodule ChatWeb.ElectricControllerReviewModerationTest do
  @moduledoc """
  HTTP ingest (`POST /electric/v1/ingest`) of origin moderation: review_public_passwords
  published and revoked by the origin identity, not the owner, under pre- and post-moderation.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3]
  import Chat.Test.ElectricReviewIngestFixtures, only: [review_ingest_parties: 2]

  import Chat.Test.ReviewFixtures,
    only: [
      insert_null_candidate: 3,
      insert_password_candidate: 3,
      insert_review: 2,
      sign_right_candidate: 3,
      unwrap_right: 2
    ]

  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData

  describe "origin moderation via HTTP ingest (pre-moderation)" do
    setup %{conn: conn}, do: review_ingest_parties(conn, :pre)

    test "origin publishes review via HTTP ingest", ctx do
      review = insert_review_for_moderation(ctx)
      run_full_promotion(ctx, review, :pre)

      post_right = PostRightData.get_post_right(review.review_hash)
      row = unwrap_right(post_right, ctx.origin_identity)
      assert row["password_b64"] != nil

      mutation = build_moderate_mutation(row)
      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.origin_identity.sign_skey)

      assert conn.status == 200, conn.resp_body

      published = PublicPasswordData.get_latest_for_review(review.review_hash)
      assert published != nil
      assert published.password_b64 != nil
    end

    test "origin revokes after publishing via HTTP ingest", ctx do
      review = insert_review_for_moderation(ctx)
      run_full_promotion(ctx, review, :pre)

      post_right = PostRightData.get_post_right(review.review_hash)
      publish_mutation = build_moderate_mutation(unwrap_right(post_right, ctx.origin_identity))

      assert post_ingest(
               ctx.conn,
               %{"mutations" => [publish_mutation]},
               ctx.origin_identity.sign_skey
             ).status == 200

      revoke_right = RevokeRightData.get_revoke_right(review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      assert null_row["password_b64"] == nil

      revoke_mutation = build_moderate_mutation(null_row)

      conn =
        post_ingest(ctx.conn, %{"mutations" => [revoke_mutation]}, ctx.origin_identity.sign_skey)

      assert conn.status == 200, conn.resp_body

      latest = PublicPasswordData.get_latest_for_review(review.review_hash)
      assert latest.password_b64 == nil
    end
  end

  describe "origin moderation via HTTP ingest (post-moderation)" do
    setup %{conn: conn}, do: review_ingest_parties(conn, :post)

    test "origin revokes auto-published review via HTTP ingest", ctx do
      review = insert_review_for_moderation(ctx)
      run_full_promotion(ctx, review, :post)

      published = PublicPasswordData.get_latest_for_review(review.review_hash)
      assert published.password_b64 != nil

      revoke_right = RevokeRightData.get_revoke_right(review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      mutation = build_moderate_mutation(null_row)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.origin_identity.sign_skey)

      assert conn.status == 200, conn.resp_body

      latest = PublicPasswordData.get_latest_for_review(review.review_hash)
      assert latest.password_b64 == nil
    end
  end

  # --- Builders ---

  defp build_moderate_mutation(unwrapped_row) do
    %{
      "type" => "insert",
      "modified" => unwrapped_row,
      "syncMetadata" => %{"relation" => "review_public_passwords"}
    }
  end

  defp insert_review_for_moderation(ctx) do
    insert_review(ctx.author, ctx.origin_hash)
  end

  defp run_full_promotion(ctx, review, mode) do
    pwd = insert_password_candidate(ctx.author, review, ctx.origin_hash)
    _null = insert_null_candidate(ctx.author, review, ctx.origin_hash)
    {:ok, _secrets} = Promotion.promote_candidate(pwd)

    case mode do
      :post ->
        sign_right_candidate(:revoke, review.review_hash, ctx.author)

      :pre ->
        sign_right_candidate(:post, review.review_hash, ctx.author)
        sign_right_candidate(:revoke, review.review_hash, ctx.author)
    end

    {:ok, _} = Promotion.complete_promotion(review.review_hash)
  end
end

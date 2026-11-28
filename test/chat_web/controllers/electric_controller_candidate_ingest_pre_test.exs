defmodule ChatWeb.ElectricControllerCandidateIngestPreTest do
  @moduledoc """
  Ingest-triggered two-phase review promotion via `POST /electric/v1/ingest` under
  pre-moderation: both right candidates, both shared secrets, both signatures to complete.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3]
  import Chat.Test.ReviewCandidateIngestFixtures

  import Chat.Test.ReviewFixtures, only: [unwrap_with_secret: 2]

  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.User, as: UserData

  setup :candidate_ingest_parties

  describe "pre mode: ingest-triggered two-phase promotion" do
    setup ctx, do: origin_with_review(ctx, :pre)

    test "both candidates create post + revoke right candidates", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      assert post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey).status ==
               200

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "promotion response includes both shared secret headers", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      [post_b64] = get_resp_header(conn, "x-review-post-shared-secret")
      [revoke_b64] = get_resp_header(conn, "x-review-revoke-shared-secret")

      post_secret = Base.decode64!(post_b64, padding: false)
      revoke_secret = Base.decode64!(revoke_b64, padding: false)

      post_rc = RightCandidateData.get_post_candidate(ctx.review.review_hash)
      revoke_rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)

      post_row = unwrap_with_secret(post_rc, post_secret)
      assert post_row["password_b64"] != nil

      revoke_row = unwrap_with_secret(revoke_rc, revoke_secret)
      assert revoke_row["password_b64"] == nil
    end

    test "signing only post right does not complete (pending)", ctx do
      {_revoke, post} = phase1_via_ingest!(ctx, :pre)

      sign_mutation = build_right_sign_mutation(post, ctx.author, :post)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
    end

    test "signing both rights completes promotion (no public password)", ctx do
      {revoke, post} = phase1_via_ingest!(ctx, :pre)

      post_sign = build_right_sign_mutation(post, ctx.author, :post)
      revoke_sign = build_right_sign_mutation(revoke, ctx.author, :revoke)

      assert post_ingest(ctx.conn, %{"mutations" => [post_sign]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [revoke_sign]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "rejects signing with wrong identity", ctx do
      {revoke, _post} = phase1_via_ingest!(ctx, :pre)

      wrong = UserData.generate_pq_identity("Wrong")
      sign_mutation = build_right_sign_mutation(revoke, wrong, :revoke)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      refute conn.status == 200
    end

    test "rejects promotion when null timestamp does not exceed password timestamp", ctx do
      base_ts = ctx.review.owner_timestamp + 100_000

      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null, timestamp: base_ts)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      refute conn.status == 200
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
    end
  end
end

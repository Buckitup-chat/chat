defmodule ChatWeb.ElectricControllerCandidateIngestTest do
  @moduledoc """
  Ingest-triggered review moderation promotion via `POST /electric/v1/ingest`.

  Tests that password candidate inserts trigger `promote_candidate` and
  right candidate signature updates trigger `complete_promotion`, replacing
  the deleted `ReviewPipelineController` endpoints. Covers `:none` and `:post` modes;
  `:pre` mode lives in `ElectricControllerCandidateIngestPreTest`, replays and batches in
  `ElectricControllerCandidateIngestReplayTest`.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3]
  import Chat.Test.ReviewCandidateIngestFixtures

  import Chat.Test.ReviewFixtures,
    only: [insert_review: 2, insert_user_card: 1, unwrap_with_secret: 2]

  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.User, as: UserData

  setup :candidate_ingest_parties

  # --- :none mode: auto-promote ---

  describe "none mode: password candidate ingest auto-promotes" do
    setup ctx, do: origin_with_review(ctx, :none)

    test "password candidate auto-promotes to review_public_passwords", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, inspect(Jason.decode!(conn.resp_body))
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end

    test "rejects candidate with wrong PoP signer", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      wrong_signer = UserData.generate_pq_identity("Impostor")

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, wrong_signer.sign_skey)

      assert conn.status in [400, 401, 422]
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "rejects candidate whose author doesn't match review", ctx do
      other = UserData.generate_pq_identity("Other")
      other_card = insert_user_card(other)
      other_review = insert_review(other, ctx.origin_hash)

      mutation =
        build_candidate_mutation_for(
          ctx.author,
          other_card.user_hash,
          other_review,
          ctx.origin_hash,
          :password
        )

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 422]
      assert PublicPasswordData.get_latest_for_review(other_review.review_hash) == nil
    end
  end

  # --- :post mode: two-phase ---

  describe "post mode: ingest-triggered two-phase promotion" do
    setup ctx, do: origin_with_review(ctx, :post)

    test "single password candidate does not trigger promotion (pending)", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
    end

    test "pending candidate returns 200 with txid, stores candidate, no promotion", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)

      assert %{"txid" => _} = Jason.decode!(conn.resp_body)
      assert conn.status == 200

      candidates = CandidateData.get_candidates_for_review(ctx.review.review_hash)
      assert length(candidates) == 1
      assert hd(candidates).author_hash == ctx.author_hash

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "both candidates trigger revoke right candidate creation", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      revoke = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      assert revoke != nil
      assert revoke.sign_b64 == nil
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
    end

    test "promotion response includes revoke shared secret header", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      [secret_b64] = get_resp_header(conn, "x-review-revoke-shared-secret")
      assert {:ok, secret} = Base.decode64(secret_b64, padding: false)
      assert byte_size(secret) > 0

      assert [] == get_resp_header(conn, "x-review-post-shared-secret")
    end

    test "shared secret from header verifies server wrapping", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      [secret_b64] = get_resp_header(conn, "x-review-revoke-shared-secret")
      shared_secret = Base.decode64!(secret_b64, padding: false)

      revoke = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      row = unwrap_with_secret(revoke, shared_secret)

      assert row["review_hash"] == ctx.review.review_hash
      assert row["author_hash"] == ctx.author_hash
      assert row["password_b64"] == nil
    end

    test "signing revoke right triggers complete_promotion", ctx do
      {revoke_candidate, _} = phase1_via_ingest!(ctx, :post)

      sign_mutation = build_right_sign_mutation(revoke_candidate, ctx.author, :revoke)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end

    test "rejects right candidate update with forged signature", ctx do
      {revoke_candidate, _} = phase1_via_ingest!(ctx, :post)

      attacker = UserData.generate_pq_identity("Attacker")
      sign_mutation = build_right_sign_mutation(revoke_candidate, attacker, :revoke)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      refute conn.status == 200
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
    end

    test "order independence: null first then password still promotes", ctx do
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      assert post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "rejects promotion when null timestamp does not exceed password timestamp", ctx do
      base_ts = ctx.review.owner_timestamp + 100_000

      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null, timestamp: base_ts)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

      refute conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
    end
  end
end

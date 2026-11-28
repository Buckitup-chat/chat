defmodule Chat.Data.ReviewModerationIntegrityTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewModerationFixtures

  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.User

  setup :review_parties

  describe "promotion rejects invalid candidates and rights" do
    test "none: rejects a password candidate whose author is not the review author", ctx do
      review = moderated_review(ctx, :none)

      attacker = User.generate_pq_identity("Attacker")
      _card = insert_user_card(attacker)
      attacker_hash = User.extract_pq_card(attacker).user_hash

      candidate =
        build_candidate(ctx.author, review, ctx.origin_hash, review.review_password,
          author_hash: attacker_hash,
          signer: attacker
        )

      assert {:error, _} = Promotion.promote_candidate(candidate)
      assert PublicPasswordData.get_latest_for_review(review.review_hash) == nil
    end

    test "none: rejects a password candidate with a forged signature", ctx do
      review = moderated_review(ctx, :none)

      attacker = User.generate_pq_identity("Attacker")

      candidate =
        build_candidate(ctx.author, review, ctx.origin_hash, review.review_password,
          signer: attacker
        )

      assert {:error, _} = Promotion.promote_candidate(candidate)
      assert PublicPasswordData.get_latest_for_review(review.review_hash) == nil
    end

    test "post: rejects when the revoke timestamp does not exceed the password timestamp", ctx do
      pwd = candidate_with_early_revoke(ctx, :post)

      assert {:error, "revoke timestamp must exceed password timestamp"} =
               Promotion.promote_candidate(pwd)
    end

    test "pre: rejects when the revoke timestamp does not exceed the password timestamp", ctx do
      pwd = candidate_with_early_revoke(ctx, :pre)

      assert {:error, "revoke timestamp must exceed password timestamp"} =
               Promotion.promote_candidate(pwd)
    end

    test "post: complete_promotion rejects a forged revoke-right signature", ctx do
      ctx = Map.put(ctx, :review, moderated_review(ctx, :post))
      promote_phase1(ctx)

      attacker = User.generate_pq_identity("Attacker")
      sign_right_candidate(:revoke, ctx.review.review_hash, attacker)

      assert {:error, :invalid_signature} = Promotion.complete_promotion(ctx.review.review_hash)
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
    end

    test "pre: complete_promotion rejects a forged post-right signature", ctx do
      ctx = Map.put(ctx, :review, moderated_review(ctx, :pre))
      promote_phase1(ctx)

      attacker = User.generate_pq_identity("Attacker")
      sign_right_candidate(:post, ctx.review.review_hash, attacker)
      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)

      assert {:error, :invalid_signature} = Promotion.complete_promotion(ctx.review.review_hash)
      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
    end

    test "post: a tampered wrapped row fails authenticated decryption", ctx do
      ctx = Map.put(ctx, :review, moderated_review(ctx, :post))
      secrets = promote_phase1(ctx)

      rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      tampered = %{rc | wrapped_row_b64: flip_last_byte(rc.wrapped_row_b64)}

      assert :failed == try_unwrap(tampered, secrets.revoke_shared_secret)
    end
  end

  defp candidate_with_early_revoke(ctx, moderation_mode) do
    review = moderated_review(ctx, moderation_mode)

    pwd = insert_password_candidate(ctx.author, review, ctx.origin_hash)
    _null = build_candidate(ctx.author, review, ctx.origin_hash, nil, timestamp_offset: -10_000)
    pwd
  end

  defp try_unwrap(right, shared_secret) do
    unwrap_with_secret(right, shared_secret)
    :decrypted
  rescue
    _ -> :failed
  catch
    _, _ -> :failed
  end

  defp flip_last_byte(bin) do
    head = binary_part(bin, 0, byte_size(bin) - 1)
    head <> <<rem(:binary.last(bin) + 1, 256)>>
  end
end

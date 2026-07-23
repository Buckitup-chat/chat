defmodule Chat.Data.ReviewModerationTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.ReviewPublicPassword.Validation, as: PublicPasswordValidation
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
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

    {:ok,
     author: author,
     owner: owner,
     origin_identity: origin_identity,
     author_hash: author_card.user_hash,
     origin_hash: origin_card.user_hash}
  end

  # --- No moderation: single-phase auto-promote ---

  describe "no moderation: auto-promotes" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "password candidate is auto-promoted to review_public_passwords", ctx do
      candidate = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)

      {:ok, _} = Promotion.promote_candidate(candidate)

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 == candidate.password_b64
    end

    test "complete_promotion returns error for :none mode", ctx do
      assert {:error, "complete_promotion not applicable for :none mode"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end
  end

  # --- Post-moderation: two-phase handshake ---

  describe "post-moderation: two-phase handshake" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "phase 1: creates revoke right candidate, returns shared_secret", ctx do
      {secrets, _pwd} = phase1_post(ctx)

      assert Map.has_key?(secrets, :revoke_shared_secret)
      assert is_binary(secrets.revoke_shared_secret)

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil

      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "phase 1: author can verify wrapping with shared_secret", ctx do
      {secrets, _pwd} = phase1_post(ctx)

      rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      row = unwrap_with_secret(rc, secrets.revoke_shared_secret)

      assert row["password_b64"] == nil
      assert row["review_hash"] == to_string(ctx.review.review_hash)
    end

    test "phase 2: after author signs, promotes password + revoke right", ctx do
      {secrets, _pwd} = phase1_post(ctx)

      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)

      {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)

      revoke = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      assert revoke != nil
      assert revoke.sign_b64 != nil

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 != nil

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert CandidateData.get_candidates_for_review(ctx.review.review_hash) == []
    end

    test "phase 2: fails if revoke right not signed", ctx do
      phase1_post(ctx)

      assert {:error, "revoke right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "origin owner can revoke after promotion", ctx do
      {_secrets, _pwd} = phase1_post(ctx)
      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)
      {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)

      revoke_right = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      assert null_row["password_b64"] == nil

      publish_password_row(null_row)

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert latest.password_b64 == nil
    end
  end

  # --- Pre-moderation: two-phase handshake ---

  describe "pre-moderation: two-phase handshake" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "phase 1: creates both right candidates, returns shared_secrets", ctx do
      {secrets, _pwd, _null} = phase1_pre(ctx)

      assert Map.has_key?(secrets, :post_shared_secret)
      assert Map.has_key?(secrets, :revoke_shared_secret)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil

      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) == nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end

    test "phase 1: author can verify both wrappings", ctx do
      {secrets, _pwd, _null} = phase1_pre(ctx)

      post_rc = RightCandidateData.get_post_candidate(ctx.review.review_hash)
      post_row = unwrap_with_secret(post_rc, secrets.post_shared_secret)
      assert post_row["password_b64"] != nil

      revoke_rc = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)
      revoke_row = unwrap_with_secret(revoke_rc, secrets.revoke_shared_secret)
      assert revoke_row["password_b64"] == nil
    end

    test "phase 2: after author signs both, promotes rights (no public password)", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)

      sign_right_candidate(:post, ctx.review.review_hash, ctx.author)
      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)

      {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)

      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
      assert CandidateData.get_candidates_for_review(ctx.review.review_hash) == []
    end

    test "phase 2: fails if only post right signed", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)

      sign_right_candidate(:post, ctx.review.review_hash, ctx.author)

      assert {:error, "revoke right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "phase 2: fails if only revoke right signed", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)

      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)

      assert {:error, "post right candidate not signed"} =
               Promotion.complete_promotion(ctx.review.review_hash)
    end

    test "origin owner approves via post_right → review visible", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)
      sign_right_candidate(:post, ctx.review.review_hash, ctx.author)
      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)
      {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)

      post_right = PostRightData.get_post_right(ctx.review.review_hash)
      row = unwrap_right(post_right, ctx.origin_identity)
      assert row["password_b64"] != nil

      publish_password_row(row)

      published = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert published != nil
      assert published.password_b64 != nil
    end

    test "origin owner revokes after approval → review hidden", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)
      sign_right_candidate(:post, ctx.review.review_hash, ctx.author)
      sign_right_candidate(:revoke, ctx.review.review_hash, ctx.author)
      {:ok, _} = Promotion.complete_promotion(ctx.review.review_hash)

      post_right = PostRightData.get_post_right(ctx.review.review_hash)
      publish_password_row(unwrap_right(post_right, ctx.origin_identity))

      revoke_right = RevokeRightData.get_revoke_right(ctx.review.review_hash)
      null_row = unwrap_right(revoke_right, ctx.origin_identity)
      assert null_row["password_b64"] == nil

      publish_password_row(null_row)

      latest = PublicPasswordData.get_latest_for_review(ctx.review.review_hash)
      assert latest.password_b64 == nil
    end

    test "fails without null candidate", ctx do
      pwd_candidate = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)

      assert {:error, "null candidate required for pre mode"} =
               Promotion.promote_candidate(pwd_candidate)
    end
  end

  # --- GC ---

  describe "right candidate garbage collection" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "delete_stale_candidates removes old unsigned candidates", ctx do
      {_secrets, _pwd, _null} = phase1_pre(ctx)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil

      RightCandidateData.delete_stale_candidates(0)

      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) == nil
    end
  end

  # --- Negative / integrity paths ---

  describe "promotion rejects invalid candidates and rights" do
    test "none: rejects a password candidate whose author is not the review author", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)

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
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)

      attacker = User.generate_pq_identity("Attacker")

      candidate =
        build_candidate(ctx.author, review, ctx.origin_hash, review.review_password,
          signer: attacker
        )

      assert {:error, _} = Promotion.promote_candidate(candidate)
      assert PublicPasswordData.get_latest_for_review(review.review_hash) == nil
    end

    test "post: rejects when the revoke timestamp does not exceed the password timestamp", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)

      pwd = insert_password_candidate(ctx.author, review, ctx.origin_hash)
      _null = build_candidate(ctx.author, review, ctx.origin_hash, nil, timestamp_offset: -10_000)

      assert {:error, "revoke timestamp must exceed password timestamp"} =
               Promotion.promote_candidate(pwd)
    end

    test "pre: rejects when the revoke timestamp does not exceed the password timestamp", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)

      pwd = insert_password_candidate(ctx.author, review, ctx.origin_hash)
      _null = build_candidate(ctx.author, review, ctx.origin_hash, nil, timestamp_offset: -10_000)

      assert {:error, "revoke timestamp must exceed password timestamp"} =
               Promotion.promote_candidate(pwd)
    end

    test "post: complete_promotion rejects a forged revoke-right signature", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      ctx = Map.put(ctx, :review, review)
      {_secrets, _pwd} = phase1_post(ctx)

      attacker = User.generate_pq_identity("Attacker")
      sign_right_candidate(:revoke, review.review_hash, attacker)

      assert {:error, :invalid_signature} = Promotion.complete_promotion(review.review_hash)
      assert RevokeRightData.get_revoke_right(review.review_hash) == nil
    end

    test "pre: complete_promotion rejects a forged post-right signature", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      ctx = Map.put(ctx, :review, review)
      {_secrets, _pwd, _null} = phase1_pre(ctx)

      attacker = User.generate_pq_identity("Attacker")
      sign_right_candidate(:post, review.review_hash, attacker)
      sign_right_candidate(:revoke, review.review_hash, ctx.author)

      assert {:error, :invalid_signature} = Promotion.complete_promotion(review.review_hash)
      assert PostRightData.get_post_right(review.review_hash) == nil
    end

    test "post: a tampered wrapped row fails authenticated decryption", ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      ctx = Map.put(ctx, :review, review)
      {secrets, _pwd} = phase1_post(ctx)

      rc = RightCandidateData.get_revoke_candidate(review.review_hash)
      tampered = %{rc | wrapped_row_b64: flip_last_byte(rc.wrapped_row_b64)}

      assert :failed == try_unwrap(tampered, secrets.revoke_shared_secret)
    end
  end

  # --- Helpers ---

  defp try_unwrap(right, shared_secret) do
    unwrap_with_secret(right, shared_secret)
    :decrypted
  rescue
    _ -> :failed
  catch
    _, _ -> :failed
  end

  defp flip_last_byte(bin) do
    size = byte_size(bin)
    <<head::binary-size(size - 1), last>> = bin
    <<head::binary, rem(last + 1, 256)>>
  end

  defp phase1_post(ctx) do
    pwd = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)
    _null = insert_null_candidate(ctx.author, ctx.review, ctx.origin_hash)
    {:ok, secrets} = Promotion.promote_candidate(pwd)
    {secrets, pwd}
  end

  defp phase1_pre(ctx) do
    pwd = insert_password_candidate(ctx.author, ctx.review, ctx.origin_hash)
    null = insert_null_candidate(ctx.author, ctx.review, ctx.origin_hash)
    {:ok, secrets} = Promotion.promote_candidate(pwd)
    {secrets, pwd, null}
  end

  defp sign_right_candidate(:post, review_hash, author) do
    candidate = RightCandidateData.get_post_candidate(review_hash)
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary()

    {:ok, _} =
      RightCandidateData.update_candidate(candidate, %{sign_b64: sign_b64, sign_hash: sign_hash})
  end

  defp sign_right_candidate(:revoke, review_hash, author) do
    candidate = RightCandidateData.get_revoke_candidate(review_hash)
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary()

    {:ok, _} =
      RightCandidateData.update_candidate(candidate, %{sign_b64: sign_b64, sign_hash: sign_hash})
  end

  defp insert_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp insert_origin(origin_identity, owner, moderation_mode) do
    origin_card = User.extract_pq_card(origin_identity)
    owner_card = User.extract_pq_card(owner)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    origin = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner_card.user_hash,
      owner_cert: owner_cert,
      name: "Test Origin",
      moderation_mode: moderation_mode,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(origin, origin_identity.sign_skey, &OriginSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:origin, :insert, signed)
    signed
  end

  defp insert_review(author, origin_hash) do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    review_password = :crypto.strong_rand_bytes(32)
    author_hash = User.extract_pq_card(author).user_hash

    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author_hash,
      content_b64: EnigmaPq.aes_gcm_encrypt("Great coffee!", review_password),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:review, :insert, signed)
    Map.put(signed, :review_password, review_password)
  end

  defp insert_password_candidate(author, review, origin_hash) do
    build_candidate(author, review, origin_hash, review.review_password)
  end

  defp insert_null_candidate(author, review, origin_hash) do
    build_candidate(author, review, origin_hash, nil, timestamp_offset: 1)
  end

  defp build_candidate(author, review, origin_hash, password_b64, opts \\ []) do
    offset = Keyword.get(opts, :timestamp_offset, 0)
    author_hash = Keyword.get(opts, :author_hash) || User.extract_pq_card(author).user_hash
    signer = Keyword.get(opts, :signer, author)
    timestamp = System.os_time(:millisecond) + offset

    signable = %Chat.Data.Schemas.ReviewPublicPassword{
      review_hash: review.review_hash,
      sign_hash: nil,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    sign_b64 = signable |> Integrity.signature_payload() |> EnigmaPq.sign(signer.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

    changeset =
      %ReviewPasswordCandidate{}
      |> ReviewPasswordCandidate.create_changeset(%{
        review_hash: review.review_hash,
        sign_hash: sign_hash,
        origin_hash: origin_hash,
        password_b64: password_b64,
        author_hash: author_hash,
        owner_timestamp: timestamp,
        sign_b64: sign_b64
      })

    {:ok, inserted} = CandidateData.insert_candidate(changeset)
    inserted
  end

  defp unwrap_right(right, origin_identity) do
    shared_secret =
      EnigmaPq.decapsulate_secret(right.kem_ciphertext_b64, origin_identity.crypt_skey)

    unwrap_with_secret(right, shared_secret)
  end

  defp unwrap_with_secret(right, shared_secret) do
    wrap_key = EnigmaPq.hkdf_derive(shared_secret, "buckitup/review-right/v1", "wrap")
    row_json = EnigmaPq.aes_gcm_decrypt(right.wrapped_row_b64, wrap_key)
    Jason.decode!(row_json)
  end

  defp publish_password_row(row) do
    sign_b64 = Base.decode64!(row["sign_b64"], padding: false)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()
    password_b64 = row["password_b64"] && Base.decode64!(row["password_b64"], padding: false)

    changes = %{
      review_hash: row["review_hash"],
      sign_hash: sign_hash,
      origin_hash: row["origin_hash"],
      password_b64: password_b64,
      author_hash: row["author_hash"],
      deleted_flag: false,
      owner_timestamp: row["owner_timestamp"],
      sign_b64: sign_b64
    }

    changeset =
      PublicPasswordValidation.validate_origin_moderate(
        %Chat.Data.Schemas.ReviewPublicPassword{},
        changes,
        :insert
      )

    {:ok, _} = PublicPasswordData.upsert_review_public_password(changeset)
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

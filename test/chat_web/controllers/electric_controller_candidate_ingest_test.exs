defmodule ChatWeb.ElectricControllerCandidateIngestTest do
  @moduledoc """
  Ingest-triggered review moderation promotion via `POST /electric/v1/ingest`.

  Tests that password candidate inserts trigger `promote_candidate` and
  right candidate signature updates trigger `complete_promotion`, replacing
  the deleted `ReviewPipelineController` endpoints.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ReviewFixtures

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.User, as: UserData
  alias EnigmaPq

  setup %{conn: conn} do
    author = UserData.generate_pq_identity("Author")
    owner = UserData.generate_pq_identity("Owner")
    origin_identity = UserData.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    _origin_card = insert_user_card(origin_identity)

    %{
      conn: conn,
      author: author,
      author_hash: author_card.user_hash,
      owner: owner,
      origin_identity: origin_identity,
      origin_hash: UserData.extract_pq_card(origin_identity).user_hash
    }
  end

  # --- :none mode: auto-promote ---

  describe "none mode: password candidate ingest auto-promotes" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

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
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

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
      {revoke_candidate, _} = phase1_via_ingest(ctx, :post)

      sign_mutation = build_right_sign_mutation(revoke_candidate, ctx.author, :revoke)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end

    test "rejects right candidate update with forged signature", ctx do
      {revoke_candidate, _} = phase1_via_ingest(ctx, :post)

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

  # --- :pre mode: two-phase ---

  describe "pre mode: ingest-triggered two-phase promotion" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

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
      {_revoke, post} = phase1_via_ingest(ctx, :pre)

      sign_mutation = build_right_sign_mutation(post, ctx.author, :post)
      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200
      assert PostRightData.get_post_right(ctx.review.review_hash) == nil
    end

    test "signing both rights completes promotion (no public password)", ctx do
      {revoke, post} = phase1_via_ingest(ctx, :pre)

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
      {revoke, _post} = phase1_via_ingest(ctx, :pre)

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

  # --- Idempotency / replay ---

  describe "idempotency: none mode duplicate candidate" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "same password candidate ingested twice → first 200, second rejected, password published",
         ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
               200

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)
      refute conn.status == 200

      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end
  end

  describe "idempotency: post mode replay" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "duplicate null candidate after phase 1 → idempotent 200", ctx do
      {_revoke, _post} = phase1_via_ingest(ctx, :post)

      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)
      conn = post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)
      assert conn.status == 200

      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "replayed signature update after completion fails", ctx do
      {revoke, _post} = phase1_via_ingest(ctx, :post)
      sign_mutation = build_right_sign_mutation(revoke, ctx.author, :revoke)

      assert post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey).status ==
               200

      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [sign_mutation]}, ctx.author.sign_skey)
      refute conn.status == 200
    end
  end

  describe "idempotency: pre mode replay" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "replayed signature update after completion fails", ctx do
      {revoke, post} = phase1_via_ingest(ctx, :pre)

      post_sign = build_right_sign_mutation(post, ctx.author, :post)
      revoke_sign = build_right_sign_mutation(revoke, ctx.author, :revoke)

      assert post_ingest(ctx.conn, %{"mutations" => [post_sign]}, ctx.author.sign_skey).status ==
               200

      assert post_ingest(ctx.conn, %{"mutations" => [revoke_sign]}, ctx.author.sign_skey).status ==
               200

      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil

      conn = post_ingest(ctx.conn, %{"mutations" => [post_sign]}, ctx.author.sign_skey)
      refute conn.status == 200
    end
  end

  # --- Batch: multiple mutations in one /ingest call ---

  describe "batch: none mode candidates in single request" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :none)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "password + null in single request → auto-promotes", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) != nil
    end
  end

  describe "batch: post mode candidates in single request" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :post)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "password + null in single request → creates revoke right candidate", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) == nil
    end

    test "null + password (reverse order) in single request → still promotes", ctx do
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [null_mutation, pwd_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end
  end

  describe "batch: pre mode candidates in single request" do
    setup ctx do
      insert_origin(ctx.origin_identity, ctx.owner, :pre)
      review = insert_review(ctx.author, ctx.origin_hash)
      {:ok, review: review}
    end

    test "password + null in single request → creates both right candidates", ctx do
      pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
      null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [pwd_mutation, null_mutation]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert RightCandidateData.get_post_candidate(ctx.review.review_hash) != nil
      assert RightCandidateData.get_revoke_candidate(ctx.review.review_hash) != nil
    end

    test "both signature updates in single request → completes promotion", ctx do
      {revoke, post} = phase1_via_ingest(ctx, :pre)

      post_sign = build_right_sign_mutation(post, ctx.author, :post)
      revoke_sign = build_right_sign_mutation(revoke, ctx.author, :revoke)

      conn =
        post_ingest(
          ctx.conn,
          %{"mutations" => [post_sign, revoke_sign]},
          ctx.author.sign_skey
        )

      assert conn.status == 200
      assert PostRightData.get_post_right(ctx.review.review_hash) != nil
      assert RevokeRightData.get_revoke_right(ctx.review.review_hash) != nil
      assert PublicPasswordData.get_latest_for_review(ctx.review.review_hash) == nil
    end
  end

  # --- Helpers ---

  defp phase1_via_ingest(ctx, mode) do
    pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
    null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

    assert post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey).status ==
             200

    assert post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey).status ==
             200

    revoke = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)

    post =
      if mode == :pre,
        do: RightCandidateData.get_post_candidate(ctx.review.review_hash),
        else: nil

    {revoke, post}
  end

  defp build_candidate_mutation(ctx, review, type, opts \\ []) do
    build_candidate_mutation_for(ctx.author, ctx.author_hash, review, ctx.origin_hash, type, opts)
  end

  defp build_candidate_mutation_for(author, author_hash, review, origin_hash, type, opts \\ []) do
    password_b64 = if type == :password, do: review.review_password
    base_ts = review.owner_timestamp + 100_000
    default_ts = if type == :null, do: base_ts + 1, else: base_ts
    ts = Keyword.get(opts, :timestamp, default_ts)

    signable = %ReviewPublicPassword{
      review_hash: review.review_hash,
      sign_hash: nil,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: ts
    }

    sign_b64 = signable |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

    modified =
      %{
        "review_hash" => review.review_hash,
        "sign_hash" => sign_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author_hash,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64)
      }
      |> maybe_put("password_b64", password_b64)

    %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "review_password_candidate"}
    }
  end

  defp build_right_sign_mutation(candidate, signer, type) do
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(signer.sign_skey)

    sign_hash =
      case type do
        :post -> sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary()
        :revoke -> sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary()
      end

    relation =
      case type do
        :post -> "review_post_right_candidate"
        :revoke -> "review_revoke_right_candidate"
      end

    %{
      "type" => "update",
      "original" => %{"review_hash" => candidate.review_hash},
      "changes" => %{
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => relation}
    }
  end

  defp to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_base64(value))

  defp post_ingest(conn, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()
    signature_b64 = challenge |> EnigmaPq.sign(sign_skey) |> Base.encode64(padding: false)

    payload =
      Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/electric/v1/ingest", Jason.encode!(payload))
  end
end

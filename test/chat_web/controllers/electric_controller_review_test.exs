defmodule ChatWeb.ElectricControllerReviewTest do
  @moduledoc """
  HTTP ingest (`POST /electric/v1/ingest`) for the review subsystem:

  - review insert with proof-of-possession auth
  - review_list insert gated by the origin's moderation proof
  - review_public_passwords moderation by origin identity, not owner (publish/revoke via HTTP)
  - author cannot directly ingest review_public_passwords (only origin identity can, owner cannot)
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ReviewFixtures

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewList, as: ReviewListData
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User, as: UserData
  alias EnigmaPq

  setup %{conn: conn} do
    author = UserData.generate_pq_identity("Author")
    owner = UserData.generate_pq_identity("Owner")
    origin_identity = UserData.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    _origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner, :none)
    origin_hash = UserData.extract_pq_card(origin_identity).user_hash

    %{
      conn: conn,
      author: author,
      author_hash: author_card.user_hash,
      origin_identity: origin_identity,
      origin_hash: origin_hash
    }
  end

  describe "review insert" do
    test "persists a signed review via HTTP ingest", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash) != nil
    end

    test "rejects a review whose PoP is signed by someone other than the author", ctx do
      {review_hash, mutation, _sign_hash} = build_review_mutation(ctx)

      wrong_signer = UserData.generate_pq_identity("Impostor")
      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, wrong_signer.sign_skey)

      assert conn.status in [400, 401, 422], conn.resp_body
      assert ReviewData.get_review(review_hash) == nil
    end
  end

  describe "review update" do
    test "persists a newer signed version (soft delete) via HTTP ingest", ctx do
      {review_hash, insert_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [insert_mutation]}, ctx.author.sign_skey).status ==
               200

      update_mutation = build_review_update_mutation(ctx, review_hash)
      conn = post_ingest(ctx.conn, %{"mutations" => [update_mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewData.get_review(review_hash).deleted_flag == true
    end
  end

  describe "review_list insert (moderation proof gate)" do
    test "persists a list entry that references a promoted password", ctx do
      {review_hash, review_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [review_mutation]}, ctx.author.sign_skey).status ==
               200

      pwd_sign_hash = promote_password(ctx, review_hash)
      mutation = build_review_list_mutation(ctx, review_hash, pwd_sign_hash)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      assert ReviewListData.get_review_list_entry(ctx.author_hash, review_hash) != nil
    end

    test "rejects a list entry whose password proof does not exist", ctx do
      {review_hash, review_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [review_mutation]}, ctx.author.sign_skey).status ==
               200

      forged = :crypto.strong_rand_bytes(64) |> ReviewPasswordSignHash.from_binary()
      mutation = build_review_list_mutation(ctx, review_hash, forged)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 422], conn.resp_body
      assert ReviewListData.get_review_list_entry(ctx.author_hash, review_hash) == nil
    end

    test "rejects a list entry whose PoP is signed by someone other than the list owner", ctx do
      {review_hash, review_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [review_mutation]}, ctx.author.sign_skey).status ==
               200

      pwd_sign_hash = promote_password(ctx, review_hash)
      mutation = build_review_list_mutation(ctx, review_hash, pwd_sign_hash)

      wrong_signer = UserData.generate_pq_identity("Impostor")
      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, wrong_signer.sign_skey)

      assert conn.status in [400, 401, 422], conn.resp_body
      assert ReviewListData.get_review_list_entry(ctx.author_hash, review_hash) == nil
    end
  end

  describe "review_public_passwords ingest posture" do
    test "author cannot directly ingest review_public_passwords (PoP rejected)", ctx do
      {review_hash, review_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [review_mutation]}, ctx.author.sign_skey).status ==
               200

      mutation = build_public_password_mutation(ctx, review_hash)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      refute conn.status == 200
      assert PublicPasswordData.get_latest_for_review(review_hash) == nil
    end

    test "non-origin identity cannot moderate review_public_passwords", ctx do
      {review_hash, review_mutation, _} = build_review_mutation(ctx)

      assert post_ingest(ctx.conn, %{"mutations" => [review_mutation]}, ctx.author.sign_skey).status ==
               200

      mutation = build_public_password_mutation(ctx, review_hash)
      impostor = UserData.generate_pq_identity("Impostor")
      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, impostor.sign_skey)

      refute conn.status == 200
      assert PublicPasswordData.get_latest_for_review(review_hash) == nil
    end
  end

  describe "origin moderation via HTTP ingest (pre-moderation)" do
    setup %{conn: conn} do
      author = UserData.generate_pq_identity("Author")
      owner = UserData.generate_pq_identity("Owner")
      origin_identity = UserData.generate_pq_identity("CoffeeShop")

      author_card = insert_user_card(author)
      _owner_card = insert_user_card(owner)
      _origin_card = insert_user_card(origin_identity)

      insert_origin(origin_identity, owner, :pre)
      origin_hash = UserData.extract_pq_card(origin_identity).user_hash

      %{
        conn: conn,
        author: author,
        author_hash: author_card.user_hash,
        origin_identity: origin_identity,
        origin_hash: origin_hash
      }
    end

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
    setup %{conn: conn} do
      author = UserData.generate_pq_identity("Author")
      owner = UserData.generate_pq_identity("Owner")
      origin_identity = UserData.generate_pq_identity("CoffeeShop")

      author_card = insert_user_card(author)
      _owner_card = insert_user_card(owner)
      _origin_card = insert_user_card(origin_identity)

      insert_origin(origin_identity, owner, :post)
      origin_hash = UserData.extract_pq_card(origin_identity).user_hash

      %{
        conn: conn,
        author: author,
        author_hash: author_card.user_hash,
        origin_identity: origin_identity,
        origin_hash: origin_hash
      }
    end

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

  defp build_review_mutation(ctx) do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    ts = System.os_time(:millisecond)

    review = %Review{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      author_hash: ctx.author_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} = sign(review, ctx.author.sign_skey, &ReviewSignHash.from_binary/1)

    mutation = %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "origin_hash" => ctx.origin_hash,
        "author_hash" => ctx.author_hash,
        "content_b64" => to_base64(review.content_b64),
        "deleted_flag" => false,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }

    {review_hash, mutation, sign_hash}
  end

  defp build_review_update_mutation(ctx, review_hash) do
    ts = System.os_time(:millisecond) + 1000
    content = :crypto.strong_rand_bytes(48)

    review = %Review{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      author_hash: ctx.author_hash,
      content_b64: content,
      deleted_flag: true,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} = sign(review, ctx.author.sign_skey, &ReviewSignHash.from_binary/1)

    %{
      "type" => "update",
      "original" => %{"review_hash" => review_hash, "author_hash" => ctx.author_hash},
      "changes" => %{
        "content_b64" => to_base64(content),
        "deleted_flag" => true,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }
  end

  defp build_review_list_mutation(ctx, review_hash, pwd_sign_hash) do
    ts = System.os_time(:millisecond)
    password_b64 = :crypto.strong_rand_bytes(32)

    rl = %ReviewList{
      user_hash: ctx.author_hash,
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: password_b64,
      review_password_sign_hash: pwd_sign_hash,
      post_right_sign_hash: nil,
      revoke_right_sign_hash: nil,
      deleted_flag: false,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} = sign(rl, ctx.author.sign_skey, &ReviewListSignHash.from_binary/1)

    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => ctx.author_hash,
        "review_hash" => review_hash,
        "origin_hash" => ctx.origin_hash,
        "password_b64" => to_base64(password_b64),
        "review_password_sign_hash" => pwd_sign_hash,
        "deleted_flag" => false,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review_list"}
    }
  end

  defp build_public_password_mutation(ctx, review_hash) do
    ts = System.os_time(:millisecond)
    password_b64 = :crypto.strong_rand_bytes(32)

    rp = %ReviewPublicPassword{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: password_b64,
      author_hash: ctx.author_hash,
      deleted_flag: false,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} = sign(rp, ctx.author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

    %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "sign_hash" => sign_hash,
        "origin_hash" => ctx.origin_hash,
        "password_b64" => to_base64(password_b64),
        "author_hash" => ctx.author_hash,
        "deleted_flag" => false,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "review_public_passwords"}
    }
  end

  # Server-internal promotion result: a review_public_passwords row inserted
  # directly (as `Promotion` would), returning its sign_hash for proof.
  defp promote_password(ctx, review_hash) do
    ts = System.os_time(:millisecond)
    password_b64 = :crypto.strong_rand_bytes(32)

    rp = %ReviewPublicPassword{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: password_b64,
      author_hash: ctx.author_hash,
      deleted_flag: false,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} = sign(rp, ctx.author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

    {:ok, _} =
      %ReviewPublicPassword{}
      |> ReviewPublicPassword.create_changeset(
        Map.merge(Map.from_struct(rp), %{sign_b64: sign_b64, sign_hash: sign_hash})
      )
      |> PublicPasswordData.upsert_review_public_password()

    sign_hash
  end

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

  defp sign(struct, sign_skey, hash_fn) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    {sign_b64, sign_b64 |> EnigmaPq.hash() |> hash_fn.()}
  end

  defp to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

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

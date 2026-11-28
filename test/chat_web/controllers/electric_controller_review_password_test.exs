defmodule ChatWeb.ElectricControllerReviewPasswordTest do
  @moduledoc """
  HTTP ingest (`POST /electric/v1/ingest`) of review passwords:

  - review_list insert gated by the origin's moderation proof
  - author cannot directly ingest review_public_passwords (only origin identity can, owner cannot)
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers,
    only: [post_ingest: 3, signature_and_hash: 3, to_base64: 1]

  import Chat.Test.ElectricReviewIngestFixtures

  alias Chat.Data.ReviewList, as: ReviewListData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.User, as: UserData

  setup %{conn: conn}, do: review_ingest_parties(conn, :none)

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

  # --- Builders ---

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

    {sign_b64, sign_hash} =
      signature_and_hash(rl, ctx.author.sign_skey, &ReviewListSignHash.from_binary/1)

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

    {sign_b64, sign_hash} =
      signature_and_hash(rp, ctx.author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

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

    {sign_b64, sign_hash} =
      signature_and_hash(rp, ctx.author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

    {:ok, _} =
      %ReviewPublicPassword{}
      |> ReviewPublicPassword.create_changeset(
        Map.merge(Map.from_struct(rp), %{sign_b64: sign_b64, sign_hash: sign_hash})
      )
      |> PublicPasswordData.upsert_review_public_password()

    sign_hash
  end
end

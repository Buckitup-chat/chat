defmodule ChatWeb.ElectricControllerReviewListUpdateTest do
  @moduledoc """
  HTTP ingest of the pre-mode `review_list` fill-in.

  In pre-moderation the author shares a review with their contacts before it is
  public, so the row goes in with no promotion proof and is updated once the
  origin publishes. This pins the contract
  `ReviewSandboxLive.ReviewList.fill_password_proof/4` has to produce: which
  columns `original` must carry, which fields belong in `changes`, and what the
  signature has to cover.
  """
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  import Chat.Test.ReviewFixtures

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.ReviewList, as: ReviewListData
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.User, as: UserData
  alias EnigmaPq

  setup %{conn: conn} do
    author = UserData.generate_pq_identity("Author")
    owner = UserData.generate_pq_identity("Owner")
    origin_identity = UserData.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    _origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner, :pre)
    origin_hash = UserData.extract_pq_card(origin_identity).user_hash

    review = insert_review(author, origin_hash)
    post_right = insert_post_right(author, review, origin_hash)
    revoke_right = insert_revoke_right(author, review, origin_hash)

    entry =
      insert_entry(%{
        conn: conn,
        author: author,
        author_hash: author_card.user_hash,
        origin_hash: origin_hash,
        review: review,
        post_sign_hash: post_right.sign_hash,
        revoke_sign_hash: revoke_right.sign_hash
      })

    %{
      conn: conn,
      author: author,
      author_hash: author_card.user_hash,
      origin_hash: origin_hash,
      review: review,
      entry: entry
    }
  end

  describe "pre-mode insert" do
    test "goes in with both rights and no promotion proof", ctx do
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)

      assert stored != nil
      assert stored.review_password_sign_hash == nil
      assert stored.post_right_sign_hash != nil
      assert stored.revoke_right_sign_hash != nil
    end
  end

  describe "filling the promotion proof after approval" do
    test "accepts an update carrying only the proof and the ordering fields", ctx do
      pwd_sign_hash = publish_password(ctx)
      mutation = fill_mutation(ctx, pwd_sign_hash)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)
      assert stored.review_password_sign_hash == pwd_sign_hash
      # Merged, not blanked: the update never sends these.
      assert stored.post_right_sign_hash == ctx.entry.post_right_sign_hash
      assert stored.revoke_right_sign_hash == ctx.entry.revoke_right_sign_hash
      assert stored.password_b64 == ctx.entry.password_b64
    end

    test "rejects a proof that references no published row", ctx do
      mutation = fill_mutation(ctx, random_password_sign_hash())

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 422], conn.resp_body
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)
      assert stored.review_password_sign_hash == nil
    end

    # The server verifies the signature against the changeset applied over the
    # stored row, so a client that signs only what it sends produces a payload
    # whose signature covers the wrong struct.
    test "rejects an update signed without the merged immutable fields", ctx do
      pwd_sign_hash = publish_password(ctx)
      mutation = fill_mutation(ctx, pwd_sign_hash, sign_over: :changes_only)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status in [400, 422], conn.resp_body
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)
      assert stored.review_password_sign_hash == nil
    end

    # Known defect, and not specific to review_list: every ingest validator that
    # runs UserValidation.validate_timestamp_newer_than_existing/1 marks a stale
    # update `action: :ignore`, and Phoenix.Sync.Writer then feeds that changeset
    # to Ecto.Multi.update/4, which refuses it — so the caller gets a 500 instead
    # of a clean rejection. The peer-sync path handles `:ignore` explicitly
    # (Shapes.ReviewList.apply_changeset/2); the HTTP path does not. Same for
    # user_card, user_storage, origin, dialog_key, message, reaction, review and
    # file. Pinned here so the fix has a failing assertion to flip.
    test "a backwards timestamp raises instead of being ignored (known defect)", ctx do
      pwd_sign_hash = publish_password(ctx)
      mutation = fill_mutation(ctx, pwd_sign_hash, owner_timestamp: ctx.entry.owner_timestamp - 1)

      assert_raise ArgumentError, ~r/action already set to :ignore/, fn ->
        post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)
      end
    end

    # Characterizes a real divergence hazard rather than endorsing it.
    # validate_timestamp_newer_than_existing/1 reads get_change/2, which is nil
    # when the cast value equals the stored one, so an equal timestamp slips
    # through and applies *here* — while review_list_upsert_query/0's
    # `owner_timestamp < EXCLUDED` guard makes every peer reject it. Since
    # owner_timestamp is unix seconds, two clicks in the same second reach this.
    # Hence ReviewList.fill_password_proof/4 uses max(previous + 1, now).
    test "applies an equal-timestamp update locally, which peers would reject", ctx do
      pwd_sign_hash = publish_password(ctx)
      mutation = fill_mutation(ctx, pwd_sign_hash, owner_timestamp: ctx.entry.owner_timestamp)

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)

      assert conn.status == 200, conn.resp_body
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)
      assert stored.review_password_sign_hash == pwd_sign_hash
      assert stored.owner_timestamp == ctx.entry.owner_timestamp
    end

    test "rejects an update whose PoP is not the list owner's", ctx do
      pwd_sign_hash = publish_password(ctx)
      mutation = fill_mutation(ctx, pwd_sign_hash)
      impostor = UserData.generate_pq_identity("Impostor")

      conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, impostor.sign_skey)

      assert conn.status in [400, 401, 422], conn.resp_body
      stored = ReviewListData.get_review_list_entry(ctx.author_hash, ctx.review.review_hash)
      assert stored.review_password_sign_hash == nil
    end
  end

  # --- Helpers ---

  defp insert_entry(ctx) do
    entry = %ReviewList{
      user_hash: ctx.author_hash,
      review_hash: ctx.review.review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: :crypto.strong_rand_bytes(48),
      review_password_sign_hash: nil,
      post_right_sign_hash: ctx.post_sign_hash,
      revoke_right_sign_hash: ctx.revoke_sign_hash,
      deleted_flag: false,
      owner_timestamp: System.os_time(:second)
    }

    {sign_b64, sign_hash} = sign(entry, ctx.author.sign_skey)

    mutation = %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => entry.user_hash,
        "review_hash" => entry.review_hash,
        "origin_hash" => entry.origin_hash,
        "password_b64" => to_base64(entry.password_b64),
        "post_right_sign_hash" => entry.post_right_sign_hash,
        "revoke_right_sign_hash" => entry.revoke_right_sign_hash,
        "deleted_flag" => false,
        "owner_timestamp" => entry.owner_timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review_list"}
    }

    conn = post_ingest(ctx.conn, %{"mutations" => [mutation]}, ctx.author.sign_skey)
    assert conn.status == 200, conn.resp_body

    entry
  end

  # Stands in for the origin decrypting its post right and ingesting the
  # author's pre-signed row.
  defp publish_password(ctx) do
    ctx.author
    |> insert_public_password(ctx.review, ctx.origin_hash)
    |> Map.fetch!(:sign_hash)
  end

  defp fill_mutation(ctx, pwd_sign_hash, opts \\ []) do
    owner_timestamp = Keyword.get(opts, :owner_timestamp, ctx.entry.owner_timestamp + 1)

    merged = %{
      ctx.entry
      | review_password_sign_hash: pwd_sign_hash,
        owner_timestamp: owner_timestamp
    }

    to_sign =
      case Keyword.get(opts, :sign_over) do
        :changes_only -> %{merged | origin_hash: nil, post_right_sign_hash: nil}
        _full -> merged
      end

    {sign_b64, sign_hash} = sign(to_sign, ctx.author.sign_skey)

    %{
      "type" => "update",
      "original" => %{
        "user_hash" => ctx.entry.user_hash,
        "review_hash" => ctx.entry.review_hash
      },
      "changes" => %{
        "review_password_sign_hash" => pwd_sign_hash,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review_list"}
    }
  end

  defp sign(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    {sign_b64, sign_b64 |> EnigmaPq.hash() |> ReviewListSignHash.from_binary()}
  end

  defp to_base64(bin), do: Base.encode64(bin, padding: false)

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

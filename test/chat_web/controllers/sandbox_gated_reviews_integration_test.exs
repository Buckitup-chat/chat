defmodule ChatWeb.SandboxGatedReviewsIntegrationTest do
  @moduledoc """
  End-to-end integration test for review gating exercising both device gate
  and origin gate via sandbox-level HTTP mutations.

  The existing `GatedReviewsIntegrationTest` covers the device gate alone.
  This test adds the origin gate (`review_access = invite_only`) and verifies
  the two gates compose correctly: a write must pass BOTH to succeed.

  All mutations (origin settings, vouch tokens, reviews) go through the
  same `/electric/v1/challenge` + `/electric/v1/ingest` path that sandbox
  LiveViews use, rather than through direct Ecto/AdminDb writes.
  The only exception is the device gate mode (`AdminDb :pq_gate_mode`),
  which has no HTTP API — the admin sandbox sets it via LiveView event.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers, only: [put_gate: 2, identity_with_card: 1]
  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1]
  import Chat.Test.SandboxIngestHelpers

  alias Chat.Data.User
  alias Chat.DeviceId
  alias Chat.Test.ReviewFixtures
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    {author, author_card} = identity_with_card("Author")

    origin_identity = User.generate_pq_identity("TestOrigin")
    origin_card = insert_user_card(origin_identity)
    origin = ReviewFixtures.insert_origin(origin_identity, owner, :none)

    conn = Sandbox.init_test_session(conn, Chat.Repo)

    %{
      conn: conn,
      owner: owner,
      owner_card: owner_card,
      author: author,
      author_card: author_card,
      origin: origin,
      origin_identity: origin_identity,
      origin_card: origin_card,
      origin_hash: origin_card.user_hash
    }
  end

  describe "origin gate" do
    test "invite_only blocks unvouched author", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")

      resp = post_review_ingest(ctx.conn, ctx.author, ctx.origin_hash)
      assert resp.status == 400
      assert resp.resp_body == "not invited"
    end

    test "token-scoped origin vouch unblocks invite_only", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")

      nonce = "tok_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

      ingest_vouch!(
        ctx.conn,
        ctx.origin_identity,
        ctx.author_card.user_hash,
        "origins.#{ctx.origin_hash}.reviews.write.#{nonce}"
      )

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)
    end

    test "broad reviews.write vouch is insufficient", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")

      ingest_vouch!(
        ctx.conn,
        ctx.origin_identity,
        ctx.author_card.user_hash,
        "origins.#{ctx.origin_hash}.reviews.write"
      )

      resp = post_review_ingest(ctx.conn, ctx.author, ctx.origin_hash)
      assert resp.status == 400
      assert resp.resp_body == "not invited"
    end

    test "origin identity can always write own reviews", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.origin_identity, ctx.origin_hash)
               |> json_response(200)
    end
  end

  describe "both gates" do
    test "device guarded + origin invite_only — requires both vouches", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")
      put_gate(:guarded, ctx.owner_card)

      nonce = "tok_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

      # No vouches → device gate blocks first (403)
      assert %{"error" => "not_in_trust_chain"} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(403)

      # Device vouch only → passes device gate, blocked by origin gate (400)
      ingest_vouch!(
        ctx.conn,
        ctx.owner,
        ctx.author_card.user_hash,
        "device.#{DeviceId.id()}.storage.write"
      )

      resp = post_review_ingest(ctx.conn, ctx.author, ctx.origin_hash)
      assert resp.status == 400
      assert resp.resp_body == "not invited"

      # Add token-scoped origin vouch → both gates pass
      ingest_vouch!(
        ctx.conn,
        ctx.origin_identity,
        ctx.author_card.user_hash,
        "origins.#{ctx.origin_hash}.reviews.write.#{nonce}"
      )

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)
    end

    test "revoking origin vouch re-blocks writes, device vouch intact", ctx do
      set_origin_review_access!(ctx.conn, ctx.origin_identity, ctx.origin_hash, "invite_only")
      put_gate(:guarded, ctx.owner_card)

      nonce = "tok_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

      ingest_vouch!(
        ctx.conn,
        ctx.owner,
        ctx.author_card.user_hash,
        "device.#{DeviceId.id()}.storage.write"
      )

      ingest_vouch!(
        ctx.conn,
        ctx.origin_identity,
        ctx.author_card.user_hash,
        "origins.#{ctx.origin_hash}.reviews.write.#{nonce}"
      )

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)

      # Revoke origin vouch
      ingest_vouch_revoke!(
        ctx.conn,
        ctx.origin_identity,
        ctx.author_card.user_hash,
        "origins.#{ctx.origin_hash}.reviews.write.#{nonce}"
      )

      resp = post_review_ingest(ctx.conn, ctx.author, ctx.origin_hash)
      assert resp.status == 400
      assert resp.resp_body == "not invited"
    end
  end
end

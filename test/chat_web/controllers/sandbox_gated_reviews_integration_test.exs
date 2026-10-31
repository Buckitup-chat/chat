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

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.DeviceId
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    {author, author_card} = identity_with_card("Author")

    origin_identity = User.generate_pq_identity("TestOrigin")
    origin_card = insert_user_card(origin_identity)
    origin = Chat.Test.ReviewFixtures.insert_origin(origin_identity, owner, :none)

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

  # --- Sandbox-style HTTP helpers ---

  defp get_challenge(conn) do
    resp = get(conn, "/electric/v1/challenge")
    json_response(resp, 200)
  end

  defp post_ingest(conn, mutations, sign_skey) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = get_challenge(conn)
    signature = challenge |> EnigmaPq.sign(sign_skey) |> b64()

    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/electric/v1/ingest",
      Jason.encode!(%{
        "auth" => %{"challenge_id" => challenge_id, "signature" => signature},
        "mutations" => mutations
      })
    )
  end

  defp post_review_ingest(conn, author, origin_hash) do
    post_ingest(conn, [review_insert_mutation(author, origin_hash)], author.sign_skey)
  end

  defp set_origin_review_access!(conn, origin_identity, origin_hash, value) do
    mutation = origin_setting_insert_mutation(origin_hash, "review_access", value, origin_identity)

    assert %{"txid" => _} =
             conn
             |> post_ingest([mutation], origin_identity.sign_skey)
             |> json_response(200)
  end

  defp ingest_vouch!(conn, issuer_identity, subject_hash, kind) do
    mutation = vouch_insert_mutation(issuer_identity, subject_hash, kind)

    assert %{"txid" => _} =
             conn
             |> post_ingest([mutation], issuer_identity.sign_skey)
             |> json_response(200)
  end

  defp ingest_vouch_revoke!(conn, issuer_identity, subject_hash, kind) do
    mutation = vouch_insert_mutation(issuer_identity, subject_hash, kind, deleted_flag: true)

    # May 409 if row exists, use update in that case
    resp = post_ingest(conn, [mutation], issuer_identity.sign_skey)

    case resp.status do
      200 ->
        :ok

      409 ->
        update = vouch_update_mutation(issuer_identity, subject_hash, kind, deleted_flag: true)

        assert %{"txid" => _} =
                 conn
                 |> post_ingest([update], issuer_identity.sign_skey)
                 |> json_response(200)
    end
  end

  # --- Mutation builders (mirror sandbox client patterns) ---

  defp origin_setting_insert_mutation(origin_hash, key, value, origin_identity) do
    setting = %OriginSetting{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 = setting |> Integrity.signature_payload() |> EnigmaPq.sign(origin_identity.sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "origin_hash" => origin_hash,
        "key" => key,
        "value" => value,
        "deleted_flag" => false,
        "owner_timestamp" => setting.owner_timestamp,
        "sign_b64" => b64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "origin_settings"}
    }
  end

  defp vouch_insert_mutation(issuer_identity, subject_hash, kind, opts \\ []) do
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    issuer_hash = User.extract_pq_card(issuer_identity).user_hash

    vouch = %VouchToken{
      kind: kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: deleted_flag
    }

    sign_b64 = vouch |> Integrity.signature_payload() |> EnigmaPq.sign(issuer_identity.sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "kind" => kind,
        "issuer_hash" => issuer_hash,
        "subject_hash" => subject_hash,
        "owner_timestamp" => vouch.owner_timestamp,
        "deleted_flag" => deleted_flag,
        "sign_b64" => b64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp vouch_update_mutation(issuer_identity, subject_hash, kind, opts) do
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    issuer_hash = User.extract_pq_card(issuer_identity).user_hash
    timestamp = System.os_time(:millisecond) + 1

    vouch = %VouchToken{
      kind: kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: timestamp,
      deleted_flag: deleted_flag
    }

    sign_b64 = vouch |> Integrity.signature_payload() |> EnigmaPq.sign(issuer_identity.sign_skey)

    %{
      "type" => "update",
      "original" => %{
        "kind" => kind,
        "issuer_hash" => issuer_hash,
        "subject_hash" => subject_hash
      },
      "changes" => %{
        "owner_timestamp" => timestamp,
        "deleted_flag" => deleted_flag,
        "sign_b64" => b64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp review_insert_mutation(author, origin_hash) do
    author_card = User.extract_pq_card(author)
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    content_b64 = EnigmaPq.aes_gcm_encrypt("Great place!", :crypto.strong_rand_bytes(32))
    timestamp = System.os_time(:millisecond)

    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author_card.user_hash,
      content_b64: content_b64,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: timestamp
    }

    sign_b64 = review |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewSignHash.from_binary()

    %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author_card.user_hash,
        "content_b64" => b64(content_b64),
        "deleted_flag" => false,
        "parent_sign_hash" => nil,
        "owner_timestamp" => timestamp,
        "sign_b64" => b64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }
  end

  defp b64(bin), do: Base.encode64(bin, padding: false)
end

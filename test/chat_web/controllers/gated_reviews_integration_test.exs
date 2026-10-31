defmodule ChatWeb.GatedReviewsIntegrationTest do
  @moduledoc """
  End-to-end integration test for review gating across all three access modes.

  Exercises the full review lifecycle through open → guarded → trust,
  verifying write gating, read gating, vouch grants, and vouch revocation.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers
  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1]

  alias Chat.Challenge
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.DeviceId
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    {author, author_card} = identity_with_card("Author")

    origin_identity = User.generate_pq_identity("TestOrigin")
    origin_card = insert_user_card(origin_identity)
    origin = insert_origin(origin_identity, owner)

    conn = Sandbox.init_test_session(conn, Chat.Repo)

    %{
      conn: conn,
      owner: owner,
      owner_card: owner_card,
      author: author,
      author_card: author_card,
      origin: origin,
      origin_hash: origin_card.user_hash
    }
  end

  defp insert_origin(origin_identity, owner) do
    Chat.Test.ReviewFixtures.insert_origin(origin_identity, owner, :none)
  end

  describe "gated reviews e2e" do
    test "phase 1: open mode — writes and reads succeed", ctx do
      put_gate(:open, ctx.owner_card)

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)

      assert get_shape(ctx.conn, "review").status == 200
    end

    test "phase 2: guarded mode — unvouched writes blocked, reads open", ctx do
      put_gate(:guarded, ctx.owner_card)

      assert %{"error" => "not_in_trust_chain", "max_depth" => 7} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(403)

      assert get_shape(ctx.conn, "review").status == 200
    end

    test "phase 3: guarded mode — write vouch unblocks writes", ctx do
      put_gate(:guarded, ctx.owner_card)
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.write")

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)
    end

    test "phase 4: trust mode — reads gated, write vouch alone insufficient for reads", ctx do
      put_gate(:trust, ctx.owner_card)
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.write")

      assert %{"error" => "read_session_required", "shape" => "review"} =
               ctx.conn |> get_shape("review") |> json_response(401)

      assert %{"error" => "not_in_trust_chain"} =
               ctx.conn
               |> post_read_session(
                 ctx.author_card.user_hash,
                 "review",
                 ctx.author.sign_skey
               )
               |> json_response(403)
    end

    test "phase 5: trust mode — read vouch enables reads, writes still work", ctx do
      put_gate(:trust, ctx.owner_card)
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.write")
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.read")

      token =
        open_read_session!(
          ctx.conn,
          ctx.author_card.user_hash,
          "review",
          ctx.author.sign_skey
        )

      assert ctx.conn |> with_bearer(token) |> get_shape("review") |> Map.get(:status) == 200

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)
    end

    test "phase 6: trust mode — revoked write vouch blocks writes, reads intact", ctx do
      put_gate(:trust, ctx.owner_card)
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.write")
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.read")

      assert %{"txid" => _} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(200)

      revoke_vouch(ctx.owner, ctx.owner_card.user_hash, ctx.author_card.user_hash, "storage.write")

      assert %{"error" => "not_in_trust_chain"} =
               ctx.conn
               |> post_review_ingest(ctx.author, ctx.origin_hash)
               |> json_response(403)

      token =
        open_read_session!(
          ctx.conn,
          ctx.author_card.user_hash,
          "review",
          ctx.author.sign_skey
        )

      assert ctx.conn |> with_bearer(token) |> get_shape("review") |> Map.get(:status) == 200
    end
  end

  # --- Private helpers ---

  defp post_review_ingest(conn, author, origin_hash) do
    {challenge_id, challenge} = Challenge.store()
    signature = challenge |> EnigmaPq.sign(author.sign_skey) |> b64()

    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/electric/v1/ingest",
      Jason.encode!(%{
        "auth" => %{"challenge_id" => challenge_id, "signature" => signature},
        "mutations" => [review_insert_mutation(author, origin_hash)]
      })
    )
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

  defp revoke_vouch(issuer_identity, issuer_hash, subject_hash, scope_suffix) do
    kind = "device.#{DeviceId.id()}.#{scope_suffix}"

    existing = VouchTokenData.get_vouch_token(kind, issuer_hash, subject_hash)
    new_ts = (existing && existing.owner_timestamp + 1) || System.os_time(:millisecond)

    {:ok, _} =
      %VouchToken{
        kind: kind,
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: new_ts,
        deleted_flag: true
      }
      |> sign_with_key(issuer_identity.sign_skey)
      |> Map.from_struct()
      |> then(&VouchToken.create_changeset(%VouchToken{}, &1))
      |> VouchTokenData.upsert_vouch_token()
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp get_shape(conn, table),
    do: get(conn, "/electric/v1/shapes", %{"table" => table, "offset" => "-1"})

  defp b64(bin), do: Base.encode64(bin, padding: false)
end

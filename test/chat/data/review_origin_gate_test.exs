defmodule Chat.Data.ReviewOriginGateTest do
  @moduledoc """
  Origin gate for review ingest: when `review_access = invite_only`,
  new reviews require a token-scoped vouch for the author
  at `origins.<origin_hash>.reviews.write.<nonce>`.

  The gate runs in the `check` phase (before changeset validation).
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.Review.Validation
  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Schemas.OriginSetting, as: OriginSettingSchema
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Phoenix.Sync.Writer.Operation

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")
    author = User.generate_pq_identity("Reviewer")
    bot = User.generate_pq_identity("ReviewBot")

    owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)
    author_card = insert_user_card(author)
    bot_card = insert_user_card(bot)

    insert_origin(origin_identity, owner)

    {:ok,
     owner: owner,
     owner_hash: owner_card.user_hash,
     origin: origin_identity,
     origin_hash: origin_card.user_hash,
     author: author,
     author_hash: author_card.user_hash,
     bot: bot,
     bot_hash: bot_card.user_hash}
  end

  describe "open mode (default)" do
    test "accepts review without vouch", ctx do
      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end
  end

  describe "invite_only mode" do
    setup ctx do
      set_review_access(ctx.origin_hash, "invite_only")
      :ok
    end

    test "rejects review without vouch", ctx do
      assert {:error, "not invited"} == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "accepts with token-scoped vouch (reviews.write.<nonce>)", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.tok_abc")
      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "rejects broad reviews.write vouch (bot-level scope)", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write")
      assert {:error, "not invited"} == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "accepts with 2-hop chain: origin→bot (reviews.write), bot→author (reviews.write.nonce)",
         ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.bot_hash, "reviews.write")

      insert_vouch(
        ctx.bot,
        ctx.bot_hash,
        ctx.author_hash,
        "origins.#{ctx.origin_hash}.reviews.write.some_nonce"
      )

      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "rejects when reviewer vouch is tombstoned", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.tok_abc",
        deleted_flag: true
      )

      assert {:error, "not invited"} == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "exempts the origin identity itself", ctx do
      assert :ok == check_insert(ctx.origin_hash, ctx.origin_hash)
    end

    test "does not exempt the origin owner", ctx do
      assert {:error, "not invited"} == check_insert(ctx.owner_hash, ctx.origin_hash)
    end

    test "does not gate updates", ctx do
      operation = %Operation{
        operation: :update,
        data: %{"review_hash" => "rh", "author_hash" => ctx.author_hash}
      }

      assert :ok == Validation.check_review_gate(operation, %{})
    end
  end

  describe "nonce validation in check phase" do
    test "passes when no nonce in pop_context", ctx do
      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "passes with valid bound token", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects when token not found", ctx do
      assert {:error, "token not found"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: "nonexistent"})
    end

    test "rejects when token already has review_hash", ctx do
      nonce =
        insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash,
          review_hash: random_review_hash()
        )

      assert {:error, "token already used"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects when token is soft-deleted", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash, deleted_flag: true)

      assert {:error, "token expired"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects when token bound to different author", ctx do
      other = User.generate_pq_identity("Other")
      other_card = insert_user_card(other)
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, other_card.user_hash)

      assert {:error, "token mismatch"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects when token belongs to different origin", ctx do
      other_origin = User.generate_pq_identity("OtherOrigin")
      other_origin_card = insert_user_card(other_origin)
      insert_origin(other_origin, ctx.owner)
      nonce = insert_bound_token(ctx.bot, other_origin_card.user_hash, ctx.author_hash)

      assert {:error, "token mismatch"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end
  end

  # --- Helpers ---

  defp check_insert(author_hash, origin_hash, pop_context \\ %{}) do
    operation = %Operation{
      operation: :insert,
      changes: %{"author_hash" => author_hash, "origin_hash" => origin_hash}
    }

    Validation.check_review_gate(operation, pop_context)
  end

  defp set_review_access(origin_hash, value) do
    Repo.insert!(%OriginSettingSchema{
      origin_hash: origin_hash,
      key: "review_access",
      value: value,
      deleted_flag: false,
      owner_timestamp: 1,
      sign_b64: <<0::256>>
    })
  end

  defp insert_origin_vouch(issuer_identity, origin_hash, subject_hash, scope_suffix, opts \\ []) do
    insert_vouch(
      issuer_identity,
      User.extract_pq_card(issuer_identity).user_hash,
      subject_hash,
      "origins.#{origin_hash}.#{scope_suffix}",
      opts
    )
  end

  defp insert_vouch(issuer_identity, issuer_hash, subject_hash, kind, opts \\ []) do
    vt =
      %VouchToken{
        kind: kind,
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond)),
        deleted_flag: Keyword.get(opts, :deleted_flag, false)
      }
      |> sign_with_key(issuer_identity.sign_skey)

    {:ok, _} =
      VouchTokenData.upsert_vouch_token(
        VouchToken.create_changeset(%VouchToken{}, Map.from_struct(vt))
      )
  end

  defp insert_bound_token(bot_identity, origin_hash, user_hash, opts \\ []) do
    nonce = "tok_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    bot_hash = User.extract_pq_card(bot_identity).user_hash

    review_hash = Keyword.get(opts, :review_hash)

    token =
      %ReviewWriteToken{
        nonce: nonce,
        origin_hash: origin_hash,
        review_bot_hash: bot_hash,
        user_hash: user_hash,
        review_hash: review_hash,
        deleted_flag: Keyword.get(opts, :deleted_flag, false),
        owner_timestamp: System.os_time(:millisecond)
      }
      |> sign_with_hash(bot_identity.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)

    {:ok, _} =
      TokenData.upsert_review_write_token(
        ReviewWriteToken.create_changeset(%ReviewWriteToken{}, Map.from_struct(token))
      )

    nonce
  end
end

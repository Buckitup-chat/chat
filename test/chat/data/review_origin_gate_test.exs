defmodule Chat.Data.ReviewOriginGateTest do
  @moduledoc """
  Origin gate for review ingest: when `review_access = invite_only`,
  new reviews require a token-scoped vouch for the author
  at `origins.<origin_hash>.reviews.write.<nonce>`.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.OriginSetting, as: OriginSettingSchema
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData

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
      changeset = validate_insert(ctx.author, ctx.origin_hash)
      assert changeset.valid?, inspect(changeset.errors)
    end
  end

  describe "invite_only mode" do
    setup ctx do
      set_review_access(ctx.origin_hash, "invite_only")
      :ok
    end

    test "rejects review without vouch", ctx do
      changeset = validate_insert(ctx.author, ctx.origin_hash)
      refute changeset.valid?
      assert {:author_hash, {"not invited", []}} in changeset.errors
    end

    test "accepts with token-scoped vouch (reviews.write.<nonce>)", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.tok_abc")
      changeset = validate_insert(ctx.author, ctx.origin_hash)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects broad reviews.write vouch (bot-level scope)", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write")
      changeset = validate_insert(ctx.author, ctx.origin_hash)
      refute changeset.valid?
      assert {:author_hash, {"not invited", []}} in changeset.errors
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

      changeset = validate_insert(ctx.author, ctx.origin_hash)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects when reviewer vouch is tombstoned", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.tok_abc",
        deleted_flag: true
      )

      changeset = validate_insert(ctx.author, ctx.origin_hash)
      refute changeset.valid?
      assert {:author_hash, {"not invited", []}} in changeset.errors
    end

    test "exempts the origin identity itself", ctx do
      changeset = validate_insert(ctx.origin, ctx.origin_hash)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "does not exempt the origin owner", ctx do
      changeset = validate_insert(ctx.owner, ctx.origin_hash)
      refute changeset.valid?
      assert {:author_hash, {"not invited", []}} in changeset.errors
    end

    test "does not gate updates (edits)", ctx do
      review = insert_review(ctx.author, ctx.origin_hash)
      updated = build_update(ctx.author, review)

      changeset =
        Validation.review_validate_with_versioning(review, Map.from_struct(updated), :update)

      assert changeset.valid?, inspect(changeset.errors)
    end
  end

  # --- Helpers ---

  defp validate_insert(author, origin_hash) do
    review = build_review(author, origin_hash)
    Validation.review_validate_with_versioning(%Review{}, Map.from_struct(review), :insert)
  end

  defp build_review(author, origin_hash) do
    %Review{
      review_hash: random_review_hash(),
      origin_hash: origin_hash,
      author_hash: User.extract_pq_card(author).user_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.os_time(:millisecond)
    }
    |> sign_with_hash(author.sign_skey, &ReviewSignHash.from_binary/1)
  end

  defp build_update(author, existing) do
    %{
      existing
      | content_b64: :crypto.strong_rand_bytes(48),
        owner_timestamp: existing.owner_timestamp + 1,
        parent_sign_hash: existing.sign_hash
    }
    |> sign_with_hash(author.sign_skey, &ReviewSignHash.from_binary/1)
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
end

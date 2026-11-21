defmodule Chat.Data.ReviewWriteTokenSetOnceTest do
  @moduledoc "user_hash / review_hash of a review write token are set-once on both update paths."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewWriteToken, as: ReviewWriteTokenData
  alias Chat.Data.ReviewWriteToken.Validation
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.User
  alias Chat.ReviewBot.Identity

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")
    bot_identity = User.generate_pq_identity("ReviewBot_CoffeeShop")

    Enum.each([owner, origin_identity, bot_identity], &insert_user_card/1)
    insert_origin(origin_identity, owner)

    {:ok,
     bot_identity: bot_identity,
     origin_hash: User.extract_pq_card(origin_identity).user_hash,
     bot_hash: User.extract_pq_card(bot_identity).user_hash,
     user_a: random_user_hash("A"),
     user_b: random_user_hash("B"),
     review_x: random_review_hash(),
     review_y: random_review_hash()}
  end

  # Both update paths run against the same cases
  for path <- [:peer_sync, :ingest] do
    describe "#{path} update" do
      test "rejects user_hash A -> B", ctx do
        existing = insert_token(ctx, user_hash: ctx.user_a)

        changeset =
          run(unquote(path), existing, signed_update(existing, ctx, user_hash: ctx.user_b))

        refute changeset.valid?
        assert Keyword.has_key?(changeset.errors, :user_hash)
      end

      test "rejects review_hash X -> Y", ctx do
        existing = insert_token(ctx, user_hash: ctx.user_a, review_hash: ctx.review_x)

        changeset =
          run(unquote(path), existing, signed_update(existing, ctx, review_hash: ctx.review_y))

        refute changeset.valid?
        assert Keyword.has_key?(changeset.errors, :review_hash)
      end

      test "accepts nil -> value", ctx do
        existing = insert_token(ctx)

        update = signed_update(existing, ctx, user_hash: ctx.user_a, review_hash: ctx.review_x)
        changeset = run(unquote(path), existing, update)

        assert changeset.valid?, inspect(changeset.errors)
      end

      test "accepts value -> same value", ctx do
        existing = insert_token(ctx, user_hash: ctx.user_a, review_hash: ctx.review_x)

        update =
          signed_update(existing, ctx,
            user_hash: ctx.user_a,
            review_hash: ctx.review_x,
            deleted_flag: true
          )

        changeset = run(unquote(path), existing, update)

        assert changeset.valid?, inspect(changeset.errors)
      end
    end
  end

  defp run(path, existing, update) do
    case path do
      :peer_sync ->
        Validation.validate_review_write_token_update(existing, update)

      :ingest ->
        update
        |> Map.from_struct()
        |> Map.take([
          :user_hash,
          :review_hash,
          :deleted_flag,
          :owner_timestamp,
          :sign_b64,
          :sign_hash
        ])
        |> then(&Validation.review_write_token_validate(existing, &1, :update))
    end
  end

  # --- Helpers ---

  defp insert_token(ctx, opts \\ []) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    token =
      %ReviewWriteToken{
        nonce_hash: ReviewWriteTokenNonceHash.from_nonce(nonce),
        nonce_enc_b64: Identity.wrap_nonce(nonce, ctx.bot_identity.crypt_skey),
        origin_hash: ctx.origin_hash,
        review_bot_hash: ctx.bot_hash,
        user_hash: Keyword.get(opts, :user_hash),
        review_hash: Keyword.get(opts, :review_hash),
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      }
      |> sign_with_hash(ctx.bot_identity.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)

    {:ok, inserted} =
      %ReviewWriteToken{}
      |> ReviewWriteToken.create_changeset(Map.from_struct(token))
      |> ReviewWriteTokenData.upsert_review_write_token()

    inserted
  end

  defp signed_update(existing, ctx, changes) do
    existing
    |> struct(changes)
    |> Map.put(:owner_timestamp, existing.owner_timestamp + 1)
    |> sign_with_hash(ctx.bot_identity.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)
  end

  defp random_user_hash(name),
    do: name |> User.generate_pq_identity() |> User.extract_pq_card() |> Map.fetch!(:user_hash)
end

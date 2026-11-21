defmodule Chat.Data.ReviewTokenGateTest do
  @moduledoc """
  Review gate for token vouches: the nonce selects the exact bind vouch
  `origins.<oh>.reviews.write.<nonce_hash>` (issuer = token bot), and in
  `invite_only` a token vouch opens nothing without its nonce.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures
  import Chat.Test.ReviewGateFixtures

  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.User

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin = User.generate_pq_identity("CoffeeShop")
    author = User.generate_pq_identity("Reviewer")
    bot = User.generate_pq_identity("ReviewBot")

    insert_user_card(owner)
    origin_hash = insert_user_card(origin).user_hash
    author_hash = insert_user_card(author).user_hash
    bot_hash = insert_user_card(bot).user_hash
    insert_origin(origin, owner)

    {:ok,
     origin: origin,
     origin_hash: origin_hash,
     author_hash: author_hash,
     bot: bot,
     bot_hash: bot_hash}
  end

  describe "exact bind vouch (any mode)" do
    test "rejects when the exact bind vouch is missing despite other origin vouches", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      other_nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, other_nonce)
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.direct")

      assert {:error, "no bind vouch"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects when the exact bind vouch is tombstoned", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce, deleted_flag: true)

      assert {:error, "no bind vouch"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "rejects an exact-kind vouch not issued by the token's bot", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      suffix = "reviews.write.#{ReviewWriteTokenNonceHash.from_nonce(nonce)}"
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, suffix)

      assert {:error, "no bind vouch"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "each of two tokens passes only with its own nonce", ctx do
      nonce_a = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      nonce_b = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce_a)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce_b)

      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce_a})
      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce_b})
    end

    test "open mode: token-only author passes without a nonce", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce)

      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end
  end

  describe "invite_only" do
    setup ctx do
      set_review_access(ctx.origin_hash, "invite_only")
      :ok
    end

    test "token-only author without a nonce gets \"nonce required\"", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.bot_hash, "reviews.write")
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce)

      assert {:error, "nonce required"} == check_insert(ctx.author_hash, ctx.origin_hash)
    end

    test "token-only author with the nonce passes", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.bot_hash, "reviews.write")
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce)

      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "nonce is refused when the bot has no chain from the origin", ctx do
      nonce = insert_bound_token(ctx.bot, ctx.origin_hash, ctx.author_hash)
      insert_bind_vouch(ctx.bot, ctx.origin_hash, ctx.author_hash, nonce)

      assert {:error, "not invited"} ==
               check_insert(ctx.author_hash, ctx.origin_hash, %{nonce: nonce})
    end

    test "direct (non-token) origin vouch passes without a nonce", ctx do
      insert_origin_vouch(ctx.origin, ctx.origin_hash, ctx.author_hash, "reviews.write.direct")

      assert :ok == check_insert(ctx.author_hash, ctx.origin_hash)
    end
  end
end

defmodule Chat.ReviewBot.TokenBinderTest do
  @moduledoc """
  `TokenBinder.bind/3` against a running bot and the real Writer: bind rules
  for order-linked tokens, reusable roots and their bound copies.
  """
  use ChatWeb.DataCase, async: false

  import Chat.Test.ReadGateHelpers, only: [identity_with_card: 1]

  import Chat.Test.ReviewBotFixtures,
    only: [setup_origin_with_bot: 0, start_bot!: 1, start_bot_registry!: 0, stop_bot!: 1]

  import Ecto.Query

  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.OriginOrderHash
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.Repo
  alias Chat.ReviewBot.TokenBinder
  alias Chat.ReviewBot.TokenCreator

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()
    ctx = setup_origin_with_bot()
    start_bot!(ctx)
    ctx
  end

  describe "order-linked token" do
    test "first bind sets user_hash and issues origin + device vouches", ctx do
      nonce = create!(ctx, order_hash())

      assert {:ok, ^nonce} = bind(ctx, nonce, ctx.reviewer)

      assert %{user_hash: user_hash} = token(nonce)
      assert user_hash == ctx.reviewer_card.user_hash
      assert bind_vouch?(ctx, nonce, ctx.reviewer_card.user_hash)
      assert device_vouch_count(ctx, ctx.reviewer_card.user_hash) == 4
    end

    test "same user binding twice is idempotent and adds no rows", ctx do
      nonce = create!(ctx, order_hash())
      {:ok, ^nonce} = bind(ctx, nonce, ctx.reviewer)
      counts = row_counts()

      assert {:ok, ^nonce} = bind(ctx, nonce, ctx.reviewer)
      assert row_counts() == counts
    end

    test "another user is refused with token_already_bound", ctx do
      nonce = create!(ctx, order_hash())
      {:ok, ^nonce} = bind(ctx, nonce, ctx.reviewer)
      {other, other_card} = identity_with_card("Other")
      counts = row_counts()

      assert {:error, :token_already_bound} = bind(ctx, nonce, other)
      assert token(nonce).user_hash == ctx.reviewer_card.user_hash
      refute bind_vouch?(ctx, nonce, other_card.user_hash)
      assert row_counts() == counts
    end
  end

  describe "reusable token" do
    test "bind mints one copy, the root stays unbound", ctx do
      root = create!(ctx)

      assert {:ok, copy} = bind(ctx, root, ctx.reviewer)
      refute copy == root

      assert %{user_hash: nil, parent_nonce_hash: nil} = token(root)
      assert %{parent_nonce_hash: parent, user_hash: user_hash} = token(copy)
      assert parent == hash(root)
      assert user_hash == ctx.reviewer_card.user_hash
      assert bind_vouch?(ctx, copy, ctx.reviewer_card.user_hash)
    end

    test "same user binding twice gets the same copy and adds no rows", ctx do
      root = create!(ctx)
      {:ok, copy} = bind(ctx, root, ctx.reviewer)
      counts = row_counts()

      assert {:ok, ^copy} = bind(ctx, root, ctx.reviewer)
      assert row_counts() == counts
    end

    test "each user gets an own copy", ctx do
      root = create!(ctx)
      {other, other_card} = identity_with_card("Other")

      {:ok, copy} = bind(ctx, root, ctx.reviewer)
      assert {:ok, other_copy} = bind(ctx, root, other)
      refute other_copy == copy
      assert token(other_copy).user_hash == other_card.user_hash
    end

    test "binding a bound copy is refused with token_not_invitation", ctx do
      {:ok, copy} = bind(ctx, create!(ctx), ctx.reviewer)
      {other, _card} = identity_with_card("Other")
      counts = row_counts()

      assert {:error, :token_not_invitation} = bind(ctx, copy, other)
      assert {:error, :token_not_invitation} = bind(ctx, copy, ctx.reviewer)
      assert row_counts() == counts
    end
  end

  describe "concurrent binds" do
    test "same user racing on a reusable root gets one copy", ctx do
      root = create!(ctx)

      copies =
        1..5
        |> Task.async_stream(fn _ -> bind(ctx, root, ctx.reviewer) end, max_concurrency: 5)
        |> Enum.map(fn {:ok, {:ok, copy}} -> copy end)

      assert [_single] = Enum.uniq(copies)
      assert copy_count(root) == 1
    end

    test "two users racing on an order-linked token bind it once", ctx do
      nonce = create!(ctx, order_hash())
      {other, _card} = identity_with_card("Other")

      results =
        [ctx.reviewer, other]
        |> Task.async_stream(&bind(ctx, nonce, &1), max_concurrency: 2)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.sort(results) == Enum.sort([{:ok, nonce}, {:error, :token_already_bound}])
    end
  end

  describe "reviewer binding several tokens" do
    test "reuses device vouches across tokens", ctx do
      {:ok, _copy} = bind(ctx, create!(ctx), ctx.reviewer)
      nonce = create!(ctx, order_hash())

      assert {:ok, ^nonce} = bind(ctx, nonce, ctx.reviewer)
      assert {:ok, _copy} = bind(ctx, create!(ctx), ctx.reviewer)
      assert device_vouch_count(ctx, ctx.reviewer_card.user_hash) == 4
    end
  end

  describe "refusals" do
    test "token not found", ctx do
      assert {:error, :token_not_found} = bind(ctx, TokenCreator.generate_nonce(), ctx.reviewer)
    end

    test "soft-deleted token", ctx do
      nonce = create!(ctx)
      update_token!(nonce, deleted_flag: true)

      assert {:error, :token_deleted} = bind(ctx, nonce, ctx.reviewer)
    end

    test "reviewer without card", ctx do
      nonce = create!(ctx)
      {challenge, signature} = pop(ctx.reviewer)
      pop = %{challenge: challenge, signature: signature}
      unknown_hash = 64 |> :crypto.strong_rand_bytes() |> UserHash.from_binary()

      assert {:error, :reviewer_not_found} = TokenBinder.bind(nonce, unknown_hash, pop)
    end

    test "invalid PoP", ctx do
      nonce = create!(ctx)
      {other, _card} = identity_with_card("Other")
      {challenge, signature} = pop(other)

      assert {:error, :invalid_pop} =
               TokenBinder.bind(nonce, ctx.reviewer_card.user_hash, %{
                 challenge: challenge,
                 signature: signature
               })
    end

    test "bot not running", ctx do
      nonce = create!(ctx)
      stop_bot!(ctx.bot_hash)

      assert {:error, :bot_not_running} = bind(ctx, nonce, ctx.reviewer)
    end

    test "bot origin vouch tombstoned", ctx do
      nonce = create!(ctx)
      tombstone_vouches!(ctx.bot_hash, "origins.#{ctx.origin_hash}.reviews.write")

      assert {:error, :no_bot_origin_vouch} = bind(ctx, nonce, ctx.reviewer)
    end

    test "bot device vouch tombstoned", ctx do
      nonce = create!(ctx)
      tombstone_vouches!(ctx.bot_hash, "device.%")

      assert {:error, :no_bot_device_vouch} = bind(ctx, nonce, ctx.reviewer)
    end
  end

  defp create!(ctx, order_hash \\ nil) do
    {:ok, nonce} = TokenCreator.create(ctx.bot_hash, order_hash)
    nonce
  end

  defp bind(_ctx, nonce, reviewer) do
    {challenge, signature} = pop(reviewer)
    reviewer_hash = User.extract_pq_card(reviewer).user_hash
    TokenBinder.bind(nonce, reviewer_hash, %{challenge: challenge, signature: signature})
  end

  defp pop(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    {challenge, EnigmaPq.sign(challenge, identity.sign_skey)}
  end

  defp order_hash, do: 64 |> :crypto.strong_rand_bytes() |> OriginOrderHash.from_binary()

  defp hash(nonce), do: ReviewWriteTokenNonceHash.from_nonce(nonce)

  defp token(nonce), do: Repo.get!(ReviewWriteToken, hash(nonce))

  defp update_token!(nonce, set) do
    from(t in ReviewWriteToken, where: t.nonce_hash == ^hash(nonce))
    |> Repo.update_all(set: set)
  end

  defp tombstone_vouches!(subject_hash, kind_like) do
    from(v in VouchToken, where: v.subject_hash == ^subject_hash and like(v.kind, ^kind_like))
    |> Repo.update_all(set: [deleted_flag: true])
  end

  defp bind_vouch?(ctx, nonce, user_hash) do
    kind = "origins.#{ctx.origin_hash}.reviews.write.#{hash(nonce)}"

    from(v in VouchToken,
      where:
        v.kind == ^kind and v.issuer_hash == ^ctx.bot_hash and v.subject_hash == ^user_hash and
          v.deleted_flag == false
    )
    |> Repo.exists?()
  end

  defp device_vouch_count(ctx, user_hash) do
    from(v in VouchToken,
      where:
        v.issuer_hash == ^ctx.bot_hash and v.subject_hash == ^user_hash and
          like(v.kind, "device.%")
    )
    |> Repo.aggregate(:count)
  end

  defp copy_count(root) do
    from(t in ReviewWriteToken, where: t.parent_nonce_hash == ^hash(root))
    |> Repo.aggregate(:count)
  end

  defp row_counts do
    {Repo.aggregate(ReviewWriteToken, :count), Repo.aggregate(VouchToken, :count)}
  end
end

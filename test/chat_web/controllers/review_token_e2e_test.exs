defmodule ChatWeb.ReviewTokenE2eTest do
  @moduledoc """
  Review write token flow end to end over HTTP: create → `GET /r/:nonce` →
  bind → review → GC, then no plaintext nonce in any public table.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReviewBotFixtures

  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Repo
  alias Chat.ReviewBot.GarbageCollector
  alias Chat.TimeKeeper
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()

    setup_origin_with_bot()
    |> Map.put(:conn, Sandbox.init_test_session(conn, Repo))
    |> tap(&start_bot!/1)
  end

  test "create → /r/:nonce → bind → review → GC stores no plaintext nonce", ctx do
    root = create_token!(ctx)
    assert ctx.conn |> get("/r/#{root}") |> Map.get(:status) == 200

    bound = bind_token!(ctx, root)
    {resp, review_hash} = post_review(ctx, bound)
    assert %{"txid" => _} = json_response(resp, 200)
    assert token(bound).review_hash == review_hash

    ctx.origin_hash
    |> TokenData.pending_expired_tokens(TimeKeeper.now_unix() + 1)
    |> GarbageCollector.soft_delete_tokens(ctx.bot_hash)

    assert token(root).deleted_flag
    refute token(bound).deleted_flag

    dump = all_public_rows()

    for nonce <- [root, bound], encoded <- [nonce, Base.encode16(nonce, case: :lower)] do
      refute dump =~ encoded
    end

    assert dump =~ ReviewWriteTokenNonceHash.from_nonce(bound)
  end

  defp token(nonce),
    do: nonce |> ReviewWriteTokenNonceHash.from_nonce() |> TokenData.get_review_write_token()

  defp all_public_rows do
    %{rows: tables} =
      Repo.query!(
        "SELECT table_name FROM information_schema.tables " <>
          "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
      )

    tables
    |> Enum.flat_map(fn [table] ->
      Repo.query!(~s(SELECT t::text FROM "#{table}" t)).rows
    end)
    |> List.flatten()
    |> Enum.join("\n")
  end
end

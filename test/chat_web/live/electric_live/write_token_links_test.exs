defmodule ChatWeb.ElectricLive.WriteTokenLinksTest do
  @moduledoc """
  Sandbox token links: the origin key unwraps the bot identity from its
  `origin_bots` row, which decrypts `nonce_enc_b64` into a `/r/<nonce>` link + QR.
  No Worker call, so a stopped bot or bad ciphertext only drops the link.
  """
  use ChatWeb.DataCase, async: false

  import Chat.Test.ReviewBotFixtures,
    only: [setup_origin_with_bot: 0, start_bot!: 1, start_bot_registry!: 0, stop_bot!: 1]

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.Types.UserHash
  alias Chat.ReviewBot.TokenCreator
  alias ChatWeb.ElectricLive.ModerationSandboxLive.WriteToken
  alias ChatWeb.ElectricLive.WriteTokenLinks

  @base_url "http://buckitup.local"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()
    ctx = setup_origin_with_bot()
    start_bot!(ctx)
    ctx
  end

  test "invitation token gets its link and QR on the sandbox's base_url", ctx do
    nonce = create!(ctx)

    assert [%{url: url, qr: qr}] = attach(ctx, [listed(nonce)])
    assert url == "#{@base_url}/r/#{nonce}"
    assert is_binary(qr)
  end

  test "moderation sandbox token list renders the link and QR", ctx do
    nonce = create!(ctx)

    html =
      %{
        origin_bots: [ctx.signed_bot],
        last_token_result: nil,
        write_tokens: attach(ctx, [listed(nonce)])
      }
      |> WriteToken.render_token_section()
      |> rendered_to_string()

    assert html =~ "/r/#{nonce}"
    assert html =~ "t-token-qr"
  end

  test "link does not need the bot running", ctx do
    nonce = create!(ctx)
    stop_bot!(ctx.bot_hash)

    assert [%{url: _}] = attach(ctx, [listed(nonce)])
  end

  test "no link for a soft-deleted token", ctx do
    assert [token] = attach(ctx, [%{listed(create!(ctx)) | deleted_flag: true}])
    refute Map.has_key?(token, :url)
  end

  test "no link for a token bound to a reviewer", ctx do
    bound = %{listed(create!(ctx)) | user_hash: ctx.reviewer_card.user_hash}

    assert [token] = attach(ctx, [bound])
    refute Map.has_key?(token, :url)
  end

  test "no link when the bot row is tombstoned or unknown", ctx do
    token = listed(create!(ctx))

    assert [t1] =
             WriteTokenLinks.attach(
               [token],
               [%{ctx.signed_bot | deleted_flag: true}],
               key(ctx),
               @base_url
             )

    assert [t2] =
             WriteTokenLinks.attach(
               [%{token | bot_hash: other_hash()}],
               [ctx.signed_bot],
               key(ctx),
               @base_url
             )

    refute Map.has_key?(t1, :url)
    refute Map.has_key?(t2, :url)
  end

  test "ciphertext that does not hash to the row's nonce_hash yields no link", ctx do
    a = listed(create!(ctx))
    b = listed(create!(ctx))

    assert [token] = attach(ctx, [%{a | nonce_enc_b64: b.nonce_enc_b64}])
    refute Map.has_key?(token, :url)
  end

  test "truncated or garbage ciphertext yields no link instead of raising", ctx do
    token = listed(create!(ctx))

    for enc <- [<<>>, <<1, 2, 3>>, :crypto.strong_rand_bytes(20), :crypto.strong_rand_bytes(64)] do
      assert [t] = attach(ctx, [%{token | nonce_enc_b64: enc}])
      refute Map.has_key?(t, :url)
    end
  end

  defp attach(ctx, tokens),
    do: WriteTokenLinks.attach(tokens, [ctx.signed_bot], key(ctx), @base_url)

  defp key(ctx), do: ctx.origin_identity.crypt_skey

  defp other_hash, do: 64 |> :crypto.strong_rand_bytes() |> UserHash.from_binary()

  defp create!(ctx) do
    {:ok, nonce} = TokenCreator.create(ctx.bot_hash)
    nonce
  end

  # Same keys as the sandbox WriteTokenClient parses from the shape
  defp listed(nonce) do
    row = nonce |> ReviewWriteTokenNonceHash.from_nonce() |> TokenData.get_review_write_token()

    row
    |> Map.take([
      :nonce_hash,
      :nonce_enc_b64,
      :origin_hash,
      :origin_order_hash,
      :user_hash,
      :review_hash,
      :parent_nonce_hash,
      :deleted_flag,
      :owner_timestamp
    ])
    |> Map.put(:bot_hash, row.review_bot_hash)
  end
end

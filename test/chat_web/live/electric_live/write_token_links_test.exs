defmodule ChatWeb.ElectricLive.WriteTokenLinksTest do
  @moduledoc """
  Sandbox token links: the running bot decrypts `nonce_enc_b64` into a full
  `/r/<nonce>` link + QR; rows alone never yield a link.
  """
  use ChatWeb.DataCase, async: false

  import Chat.Test.ReviewBotFixtures,
    only: [setup_origin_with_bot: 0, start_bot!: 1, start_bot_registry!: 0, stop_bot!: 1]

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.ReviewBot.TokenCreator
  alias Chat.ReviewBot.Worker
  alias ChatWeb.ElectricLive.OriginSandboxLive.WriteToken
  alias ChatWeb.ElectricLive.WriteTokenLinks

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    start_bot_registry!()
    ctx = setup_origin_with_bot()
    start_bot!(ctx)
    ctx
  end

  test "own token gets its full link and QR from the bot", ctx do
    nonce = create!(ctx)

    assert [%{url: url, qr: qr}] = WriteTokenLinks.attach([listed(nonce)])
    assert url == "#{ChatWeb.Endpoint.url()}/r/#{nonce}"
    assert is_binary(qr)
  end

  test "origin sandbox token list renders the link and QR", ctx do
    nonce = create!(ctx)

    html =
      %{
        origin_bots: [%{bot_hash: ctx.bot_hash, deleted_flag: false}],
        last_token_result: nil,
        write_tokens: WriteTokenLinks.attach([listed(nonce)])
      }
      |> WriteToken.render_token_section()
      |> rendered_to_string()

    assert html =~ "/r/#{nonce}"
    assert html =~ "t-token-qr"
  end

  test "no link when the bot is not running", ctx do
    nonce = create!(ctx)
    stop_bot!(ctx.bot_hash)

    assert [token] = WriteTokenLinks.attach([listed(nonce)])
    refute Map.has_key?(token, :url)
  end

  test "no link for a soft-deleted token", ctx do
    nonce = create!(ctx)

    assert [token] = WriteTokenLinks.attach([%{listed(nonce) | deleted_flag: true}])
    refute Map.has_key?(token, :url)
  end

  test "bot refuses a ciphertext that does not hash to the row's nonce_hash", ctx do
    a = listed(create!(ctx))
    b = listed(create!(ctx))
    swapped = %{a | nonce_enc_b64: b.nonce_enc_b64}

    assert {:error, :nonce_mismatch} = Worker.reveal_nonce(ctx.bot_hash, swapped)
    assert [token] = WriteTokenLinks.attach([swapped])
    refute Map.has_key?(token, :url)
  end

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

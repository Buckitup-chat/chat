defmodule Chat.ReviewBot.IdentityTest do
  use ExUnit.Case, async: true

  alias Chat.Data.User
  alias Chat.ReviewBot.Identity

  setup do
    bot = User.generate_pq_identity("TestBot")
    bot_card = User.extract_pq_card(bot)
    origin = User.generate_pq_identity("TestOrigin")
    {:ok, bot: bot, bot_card: bot_card, origin: origin}
  end

  describe "encode/decode round-trip" do
    test "encodes and decodes identity", ctx do
      encoded = Identity.encode(ctx.bot)
      assert {:ok, decoded} = Identity.decode(encoded)
      assert decoded.sign_skey == ctx.bot.sign_skey
      assert decoded.crypt_skey == ctx.bot.crypt_skey
    end

    test "rejects invalid JSON" do
      assert {:error, _} = Identity.decode("not json")
    end

    test "rejects missing version" do
      json = Jason.encode!(%{"sign_skey" => "a", "crypt_skey" => "b"})
      assert {:error, _} = Identity.decode(json)
    end
  end

  describe "wrap/unwrap round-trip" do
    test "wraps to origin crypt_pkey, unwraps with crypt_skey", ctx do
      {secret, encrypted} = Identity.wrap(ctx.bot, ctx.origin.crypt_pkey)

      assert is_binary(secret)
      assert is_binary(encrypted)

      assert {:ok, unwrapped} = Identity.unwrap(secret, encrypted, ctx.origin.crypt_skey)
      assert unwrapped.sign_skey == ctx.bot.sign_skey
      assert unwrapped.crypt_skey == ctx.bot.crypt_skey
    end

    test "fails with wrong crypt_skey", ctx do
      {secret, encrypted} = Identity.wrap(ctx.bot, ctx.origin.crypt_pkey)
      stranger = User.generate_pq_identity("Stranger")
      assert {:error, _} = Identity.unwrap(secret, encrypted, stranger.crypt_skey)
    end
  end

  describe "wrap_token/unwrap_token round-trip" do
    test "wraps to origin crypt_pkey, unwraps with crypt_skey", ctx do
      {secret, encrypted} = Identity.wrap_token("s3cr3t-bearer-token", ctx.origin.crypt_pkey)

      assert is_binary(secret)
      assert is_binary(encrypted)

      assert {:ok, "s3cr3t-bearer-token"} =
               Identity.unwrap_token(secret, encrypted, ctx.origin.crypt_skey)
    end

    test "uses a distinct salt from identity wrap/unwrap" do
      refute Identity.auth_token_salt() == Identity.origin_salt()
    end

    test "fails with wrong crypt_skey", ctx do
      {secret, encrypted} = Identity.wrap_token("s3cr3t-bearer-token", ctx.origin.crypt_pkey)
      stranger = User.generate_pq_identity("Stranger")
      assert {:error, _} = Identity.unwrap_token(secret, encrypted, stranger.crypt_skey)
    end

    test "handles nil auth token gracefully on wrap", ctx do
      assert {nil, nil} = Identity.wrap_token(nil, ctx.origin.crypt_pkey)
    end

    test "handles nil auth token gracefully on unwrap", ctx do
      assert {:ok, nil} = Identity.unwrap_token(nil, nil, ctx.origin.crypt_skey)
    end
  end

  describe "matches_card?/2" do
    test "returns true for matching identity and card", ctx do
      assert Identity.matches_card?(ctx.bot, ctx.bot_card)
    end

    test "returns false for mismatched identity and card", ctx do
      other = User.generate_pq_identity("Other")
      other_card = User.extract_pq_card(other)
      refute Identity.matches_card?(ctx.bot, other_card)
    end
  end
end

defmodule Chat.ReviewBot.WorkerTest do
  use ExUnit.Case, async: true

  alias Chat.Data.User
  alias Chat.ReviewBot.Worker

  setup do
    bot = User.generate_pq_identity("TestBot")
    bot_card = User.extract_pq_card(bot)
    origin = User.generate_pq_identity("TestOrigin")
    origin_card = User.extract_pq_card(origin)

    start_supervised!({Registry, keys: :unique, name: Chat.ReviewBot.Registry})

    identity = %{sign_skey: bot.sign_skey, crypt_skey: bot.crypt_skey}

    {:ok, bot: bot, bot_card: bot_card, origin_card: origin_card, identity: identity}
  end

  describe "start_link and lifecycle" do
    test "starts and registers via bot_hash", ctx do
      start_worker!(ctx)
      assert Worker.running?(ctx.bot_card.user_hash)
    end

    test "whereis returns pid when running", ctx do
      start_worker!(ctx)
      assert is_pid(Worker.whereis(ctx.bot_card.user_hash))
    end

    test "whereis returns nil when not running", ctx do
      assert Worker.whereis(ctx.bot_card.user_hash) == nil
    end
  end

  describe "info/1" do
    test "returns bot_hash and origin_hash without secrets", ctx do
      start_worker!(ctx)
      info = Worker.info(ctx.bot_card.user_hash)
      assert info.bot_hash == ctx.bot_card.user_hash
      assert info.origin_hash == ctx.origin_card.user_hash
      refute Map.has_key?(info, :identity)
    end
  end

  describe "sign/2" do
    test "signs payload with bot's sign_skey", ctx do
      start_worker!(ctx)
      payload = :crypto.strong_rand_bytes(32)
      signature = Worker.sign(ctx.bot_card.user_hash, payload)
      assert EnigmaPq.verify(payload, signature, ctx.bot_card.sign_pkey)
    end
  end

  describe "format_status/1" do
    test "redacts identity from status", ctx do
      start_worker!(ctx)
      pid = Worker.whereis(ctx.bot_card.user_hash)
      status = :sys.get_status(pid)

      status_str = inspect(status)
      refute status_str =~ inspect(ctx.identity.sign_skey)
      refute status_str =~ inspect(ctx.identity.crypt_skey)
      assert status_str =~ ":redacted"
    end
  end

  defp start_worker!(ctx) do
    start_supervised!(
      {Worker,
       %{
         bot_hash: ctx.bot_card.user_hash,
         origin_hash: ctx.origin_card.user_hash,
         identity: ctx.identity
       }}
    )
  end
end

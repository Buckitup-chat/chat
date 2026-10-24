defmodule Chat.ReviewBot.WorkerGcTest do
  use ExUnit.Case, async: false
  import Rewire

  alias Chat.Data.User

  defmodule FakeGC do
    def run(bot_hash, origin_hash) do
      send(:worker_gc_test, {:gc_ran, bot_hash, origin_hash})
    end
  end

  setup do
    Process.register(self(), :worker_gc_test)

    bot = User.generate_pq_identity("GCBot")
    bot_card = User.extract_pq_card(bot)
    origin = User.generate_pq_identity("GCOrigin")
    origin_card = User.extract_pq_card(origin)

    start_supervised!({Registry, keys: :unique, name: Chat.ReviewBot.Registry})

    on_exit(fn ->
      try do
        Process.unregister(:worker_gc_test)
      rescue
        _ -> :ok
      end
    end)

    {:ok,
     bot_card: bot_card,
     origin_card: origin_card,
     identity: %{sign_skey: bot.sign_skey, crypt_skey: bot.crypt_skey}}
  end

  test "runs GC when :gc_tick is received", ctx do
    worker = rewire(Chat.ReviewBot.Worker, GarbageCollector: FakeGC)

    {:ok, pid} =
      worker.start_link(%{
        bot_hash: ctx.bot_card.user_hash,
        origin_hash: ctx.origin_card.user_hash,
        identity: ctx.identity
      })

    send(pid, :gc_tick)

    assert_receive {:gc_ran, bot_hash, origin_hash}, 500
    assert bot_hash == ctx.bot_card.user_hash
    assert origin_hash == ctx.origin_card.user_hash
  end
end

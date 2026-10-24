defmodule Chat.ReviewBot.GarbageCollectorTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Data.Schemas.ReviewWriteToken

  @bot_hash "u_" <> String.duplicate("ab", 64)
  @origin_hash "u_" <> String.duplicate("cd", 64)
  @now 1_700_000_000

  defmodule FakeTimeKeeper do
    def now_unix, do: 1_700_000_000
  end

  defmodule FakeOriginSetting do
    def get_review_token_ttl_days(_), do: 7
  end

  defmodule FakeWorker do
    def sign(_, _), do: :crypto.strong_rand_bytes(100)

    def ingest(bot_hash, mutations) do
      send(self(), {:ingested, bot_hash, mutations})
      {:ok, 1, []}
    end
  end

  defmodule OneExpired do
    @origin_hash "u_" <> String.duplicate("cd", 64)
    @bot_hash "u_" <> String.duplicate("ab", 64)
    @expired_ts 1_700_000_000 - 8 * 86_400

    def pending_expired_tokens(@origin_hash, _threshold) do
      [
        %ReviewWriteToken{
          nonce: "expired_1",
          origin_hash: @origin_hash,
          review_bot_hash: @bot_hash,
          origin_order_hash: nil,
          parent_nonce: nil,
          user_hash: nil,
          review_hash: nil,
          deleted_flag: false,
          owner_timestamp: @expired_ts,
          sign_b64: :crypto.strong_rand_bytes(100),
          sign_hash: "rwt_sign_" <> String.duplicate("00", 64)
        }
      ]
    end
  end

  defmodule NoExpired do
    def pending_expired_tokens(_, _), do: []
  end

  defmodule TwoExpired do
    @origin_hash "u_" <> String.duplicate("cd", 64)
    @bot_hash "u_" <> String.duplicate("ab", 64)

    def pending_expired_tokens(@origin_hash, _threshold) do
      for {nonce, ts} <- [{"n1", 1_700_000_000 - 8 * 86_400}, {"n2", 1_700_000_000 - 15 * 86_400}] do
        %ReviewWriteToken{
          nonce: nonce,
          origin_hash: @origin_hash,
          review_bot_hash: @bot_hash,
          origin_order_hash: nil,
          parent_nonce: nil,
          user_hash: nil,
          review_hash: nil,
          deleted_flag: false,
          owner_timestamp: ts,
          sign_b64: :crypto.strong_rand_bytes(100),
          sign_hash: "rwt_sign_" <> String.duplicate("00", 64)
        }
      end
    end
  end

  describe "run/2" do
    test "soft-deletes expired pending tokens" do
      gc =
        rewire(Chat.ReviewBot.GarbageCollector,
          Worker: FakeWorker,
          TimeKeeper: FakeTimeKeeper,
          OriginSetting: FakeOriginSetting,
          TokenQueries: OneExpired
        )

      gc.run(@bot_hash, @origin_hash)

      assert_received {:ingested, @bot_hash, [mutation]}
      assert mutation["modified"]["deleted_flag"] == true
      assert mutation["modified"]["nonce"] == "expired_1"
      assert mutation["type"] == "insert"
    end

    test "owner_timestamp bump is +1, not bot clock" do
      gc =
        rewire(Chat.ReviewBot.GarbageCollector,
          Worker: FakeWorker,
          TimeKeeper: FakeTimeKeeper,
          OriginSetting: FakeOriginSetting,
          TokenQueries: OneExpired
        )

      gc.run(@bot_hash, @origin_hash)

      expected_ts = @now - 8 * 86_400 + 1
      assert_received {:ingested, _, [mutation]}
      assert mutation["modified"]["owner_timestamp"] == expected_ts
      assert mutation["modified"]["owner_timestamp"] != @now
    end

    test "does not touch anything when no tokens expired" do
      gc =
        rewire(Chat.ReviewBot.GarbageCollector,
          Worker: FakeWorker,
          TimeKeeper: FakeTimeKeeper,
          OriginSetting: FakeOriginSetting,
          TokenQueries: NoExpired
        )

      gc.run(@bot_hash, @origin_hash)

      refute_received {:ingested, _, _}
    end

    test "processes each expired token separately" do
      gc =
        rewire(Chat.ReviewBot.GarbageCollector,
          Worker: FakeWorker,
          TimeKeeper: FakeTimeKeeper,
          OriginSetting: FakeOriginSetting,
          TokenQueries: TwoExpired
        )

      gc.run(@bot_hash, @origin_hash)

      assert_received {:ingested, @bot_hash, [m1]}
      assert_received {:ingested, @bot_hash, [m2]}
      nonces = MapSet.new([m1["modified"]["nonce"], m2["modified"]["nonce"]])
      assert MapSet.equal?(nonces, MapSet.new(["n1", "n2"]))
    end
  end
end

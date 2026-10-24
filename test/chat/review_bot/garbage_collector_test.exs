defmodule Chat.ReviewBot.GarbageCollectorTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Data.Schemas.ReviewWriteToken

  @bot_hash "u_" <> String.duplicate("ab", 64)
  @origin_hash "u_" <> String.duplicate("cd", 64)

  defmodule FakeWorker do
    def sign(_, _), do: :crypto.strong_rand_bytes(100)

    def ingest(bot_hash, mutations) do
      send(self(), {:ingested, bot_hash, mutations})
      {:ok, 1, []}
    end
  end

  defp expired_token(nonce, ts) do
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

  defp gc do
    rewire(Chat.ReviewBot.GarbageCollector, Worker: FakeWorker)
  end

  describe "soft_delete_tokens/2" do
    test "soft-deletes expired pending tokens" do
      token = expired_token("expired_1", 1_000_000)

      gc().soft_delete_tokens([token], @bot_hash)

      assert_received {:ingested, @bot_hash, [mutation]}
      assert mutation["modified"]["deleted_flag"] == true
      assert mutation["modified"]["nonce"] == "expired_1"
      assert mutation["type"] == "insert"
    end

    test "owner_timestamp bump is +1, not bot clock" do
      ts = 1_700_000_000
      token = expired_token("expired_1", ts)

      gc().soft_delete_tokens([token], @bot_hash)

      assert_received {:ingested, _, [mutation]}
      assert mutation["modified"]["owner_timestamp"] == ts + 1
    end

    test "does not touch anything when no tokens" do
      gc().soft_delete_tokens([], @bot_hash)

      refute_received {:ingested, _, _}
    end

    test "processes each expired token separately" do
      tokens = [expired_token("n1", 1_000), expired_token("n2", 2_000)]

      gc().soft_delete_tokens(tokens, @bot_hash)

      assert_received {:ingested, @bot_hash, [m1]}
      assert_received {:ingested, @bot_hash, [m2]}
      nonces = MapSet.new([m1["modified"]["nonce"], m2["modified"]["nonce"]])
      assert MapSet.equal?(nonces, MapSet.new(["n1", "n2"]))
    end
  end
end

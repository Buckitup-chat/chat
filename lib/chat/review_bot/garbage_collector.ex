defmodule Chat.ReviewBot.GarbageCollector do
  @moduledoc "Soft-deletes expired pending review write tokens for a review bot."

  alias Chat.Data.Integrity
  alias Chat.Data.OriginSetting
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.ReviewBot.TokenQueries
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @seconds_per_day 86_400

  def run(bot_hash, origin_hash) do
    ttl_days = OriginSetting.get_review_token_ttl_days(origin_hash)
    threshold_ts = TimeKeeper.now_unix() - ttl_days * @seconds_per_day

    origin_hash
    |> TokenQueries.pending_expired_tokens(threshold_ts)
    |> Enum.each(&soft_delete(bot_hash, &1))
  end

  defp soft_delete(bot_hash, %ReviewWriteToken{} = token) do
    updated = %ReviewWriteToken{
      token
      | deleted_flag: true,
        owner_timestamp: token.owner_timestamp + 1
    }

    payload = Integrity.signature_payload(updated)
    sign_b64 = Worker.sign(bot_hash, payload)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewWriteTokenSignHash.from_binary()

    signed = %{updated | sign_b64: sign_b64, sign_hash: sign_hash}

    Worker.ingest(bot_hash, [build_mutation(signed)])
  end

  defp build_mutation(token) do
    %{
      "type" => "insert",
      "modified" => %{
        "nonce" => token.nonce,
        "origin_hash" => token.origin_hash,
        "review_bot_hash" => token.review_bot_hash,
        "origin_order_hash" => token.origin_order_hash,
        "parent_nonce" => token.parent_nonce,
        "user_hash" => token.user_hash,
        "review_hash" => token.review_hash,
        "deleted_flag" => token.deleted_flag,
        "owner_timestamp" => token.owner_timestamp,
        "sign_b64" => token.sign_b64,
        "sign_hash" => token.sign_hash
      },
      "syncMetadata" => %{"relation" => "review_write_tokens"}
    }
  end
end

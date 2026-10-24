defmodule Chat.ReviewBot.GarbageCollector do
  @moduledoc "Soft-deletes expired pending review write tokens for a review bot."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.ReviewBot.Worker

  def soft_delete_tokens(tokens, bot_hash) do
    Enum.each(tokens, &soft_delete(bot_hash, &1))
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

defmodule Chat.ReviewBot.TokenCreator do
  @moduledoc "Creates review write tokens on behalf of a running review bot."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.VouchToken
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @nonce_bytes 24

  def create(bot_hash, origin_order_hash \\ nil) do
    with {:ok, %{origin_hash: origin_hash}} <- fetch_bot_info(bot_hash),
         :ok <- verify_live_vouch(origin_hash, bot_hash),
         nonce <- generate_nonce(),
         {:ok, token} <- build_and_sign(bot_hash, origin_hash, nonce, origin_order_hash),
         {:ok, _txid, _changes} <- ingest_token(bot_hash, token) do
      {:ok, nonce}
    end
  end

  defp fetch_bot_info(bot_hash) do
    case Worker.running?(bot_hash) do
      true -> {:ok, Worker.info(bot_hash)}
      false -> {:error, :bot_not_running}
    end
  end

  defp verify_live_vouch(origin_hash, bot_hash) do
    kind = "origins.#{origin_hash}.reviews.write"

    case VouchToken.get_vouch_token(kind, origin_hash, bot_hash) do
      %{deleted_flag: false} -> :ok
      _ -> {:error, :no_live_vouch}
    end
  end

  defp generate_nonce do
    @nonce_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp build_and_sign(bot_hash, origin_hash, nonce, origin_order_hash) do
    struct = %ReviewWriteToken{
      nonce: nonce,
      origin_hash: origin_hash,
      review_bot_hash: bot_hash,
      origin_order_hash: origin_order_hash,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    payload = Integrity.signature_payload(struct)
    sign_b64 = Worker.sign(bot_hash, payload)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewWriteTokenSignHash.from_binary()

    {:ok, %{struct | sign_b64: sign_b64, sign_hash: sign_hash}}
  end

  defp ingest_token(bot_hash, token) do
    Worker.ingest(bot_hash, [build_mutation(token)])
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

defmodule Chat.ReviewBot.TokenCreator do
  @moduledoc "Creates review write tokens on behalf of a running review bot."

  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.VouchToken
  alias Chat.ReviewBot.RowBuilder
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @nonce_bytes 24

  def create(bot_hash, origin_order_hash \\ nil) do
    with {:ok, %{origin_hash: origin_hash}} <- fetch_bot_info(bot_hash),
         :ok <- verify_live_vouch(origin_hash, bot_hash),
         nonce <- generate_nonce(),
         token <- build(bot_hash, origin_hash, nonce, origin_order_hash),
         {:ok, _txid, _changes} <- ingest_token(bot_hash, token) do
      {:ok, nonce}
    end
  end

  def generate_nonce do
    @nonce_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
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

  defp build(bot_hash, origin_hash, nonce, origin_order_hash) do
    %ReviewWriteToken{
      nonce_hash: ReviewWriteTokenNonceHash.from_nonce(nonce),
      nonce_enc_b64: Worker.wrap_nonce(bot_hash, nonce),
      origin_hash: origin_hash,
      review_bot_hash: bot_hash,
      origin_order_hash: origin_order_hash,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }
  end

  defp ingest_token(bot_hash, token) do
    Worker.ingest(bot_hash, [RowBuilder.review_write_token_mutation(token)])
  end
end

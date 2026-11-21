defmodule Chat.ReviewBot.GarbageCollector do
  @moduledoc "Soft-deletes expired pending review write tokens for a review bot."

  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.ReviewBot.RowBuilder
  alias Chat.ReviewBot.Worker

  def soft_delete_tokens(tokens, bot_hash) do
    Enum.each(tokens, &soft_delete(bot_hash, &1))
  end

  defp soft_delete(bot_hash, %ReviewWriteToken{} = token) do
    %ReviewWriteToken{token | deleted_flag: true, owner_timestamp: token.owner_timestamp + 1}
    |> RowBuilder.review_write_token_mutation()
    |> List.wrap()
    |> then(&Worker.ingest(bot_hash, &1))
  end
end

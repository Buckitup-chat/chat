defmodule Chat.ReviewBot.TokenQueries do
  @moduledoc "Query helpers for review write token GC."

  alias Chat.Data.ReviewWriteToken

  defdelegate pending_expired_tokens(origin_hash, threshold_ts), to: ReviewWriteToken
end

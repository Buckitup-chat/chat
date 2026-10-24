defmodule Chat.ReviewBot.BinderQueries do
  @moduledoc false

  alias Chat.Data.ReviewWriteToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken

  defdelegate get_review_write_token(nonce), to: ReviewWriteToken
  defdelegate get_card(user_hash), to: User
  defdelegate valid_card?(card), to: User
  defdelegate get_vouch_token(kind, issuer_hash, subject_hash), to: VouchToken
  defdelegate scoped_vouch_exists?(subject_hash, scope_prefix), to: VouchToken
end

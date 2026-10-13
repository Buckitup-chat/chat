defmodule Chat.Data.Types.ReviewWriteTokenSignHash do
  @moduledoc "Signature hash for review write token records. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash,
    prefix: Chat.Data.Types.Consts.review_write_token_sign_prefix()
end

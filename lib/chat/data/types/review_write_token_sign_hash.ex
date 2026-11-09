defmodule Chat.Data.Types.ReviewWriteTokenSignHash do
  @moduledoc "Signature hash for review write token records. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash,
    prefix: Consts.review_write_token_sign_prefix()
end

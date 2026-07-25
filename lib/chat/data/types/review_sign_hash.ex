defmodule Chat.Data.Types.ReviewSignHash do
  @moduledoc "Signature hash identifying a specific version of a review record. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.review_sign_prefix()
end

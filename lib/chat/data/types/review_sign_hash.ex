defmodule Chat.Data.Types.ReviewSignHash do
  @moduledoc "Signature hash identifying a specific version of a review record. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.review_sign_prefix()
end

defmodule Chat.Data.Types.ReviewListSignHash do
  @moduledoc "Signature hash for review_list entries. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.review_list_sign_prefix()
end

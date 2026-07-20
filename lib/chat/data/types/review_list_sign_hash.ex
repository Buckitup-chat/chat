defmodule Chat.Data.Types.ReviewListSignHash do
  @moduledoc "Signature hash for review_list entries. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.review_list_sign_prefix()
end

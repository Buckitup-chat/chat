defmodule Chat.Data.Types.ReviewPostRightSignHash do
  @moduledoc "Signature hash for review_post_right entries. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.review_post_right_sign_prefix()
end

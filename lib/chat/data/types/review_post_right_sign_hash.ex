defmodule Chat.Data.Types.ReviewPostRightSignHash do
  @moduledoc "Signature hash for review_post_right entries. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.review_post_right_sign_prefix()
end

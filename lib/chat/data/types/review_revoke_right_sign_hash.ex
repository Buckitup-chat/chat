defmodule Chat.Data.Types.ReviewRevokeRightSignHash do
  @moduledoc "Signature hash for review_revoke_right entries. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash,
    prefix: Consts.review_revoke_right_sign_prefix()
end

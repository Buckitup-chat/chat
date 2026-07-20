defmodule Chat.Data.Types.ReviewRevokeRightSignHash do
  @moduledoc "Signature hash for review_revoke_right entries. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash,
    prefix: Chat.Data.Types.Consts.review_revoke_right_sign_prefix()
end

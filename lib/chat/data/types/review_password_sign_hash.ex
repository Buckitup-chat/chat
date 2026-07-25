defmodule Chat.Data.Types.ReviewPasswordSignHash do
  @moduledoc "Signature hash for review_passwords entries. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.review_password_sign_prefix()
end

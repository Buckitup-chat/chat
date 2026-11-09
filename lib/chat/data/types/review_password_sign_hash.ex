defmodule Chat.Data.Types.ReviewPasswordSignHash do
  @moduledoc "Signature hash for review_passwords entries. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.review_password_sign_prefix()
end

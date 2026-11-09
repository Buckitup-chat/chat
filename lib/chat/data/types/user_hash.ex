defmodule Chat.Data.Types.UserHash do
  @moduledoc "Unique identifier derived from a user's public key. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.user_prefix()
end

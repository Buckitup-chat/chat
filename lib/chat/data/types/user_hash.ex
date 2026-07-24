defmodule Chat.Data.Types.UserHash do
  @moduledoc "Unique identifier derived from a user's public key. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.user_prefix()
end

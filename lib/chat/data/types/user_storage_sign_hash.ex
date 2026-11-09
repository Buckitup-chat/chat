defmodule Chat.Data.Types.UserStorageSignHash do
  @moduledoc "Signature hash identifying a specific version of a user storage entry. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.user_storage_sign_prefix()
end

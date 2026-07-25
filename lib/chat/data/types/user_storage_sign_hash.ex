defmodule Chat.Data.Types.UserStorageSignHash do
  @moduledoc "Signature hash identifying a specific version of a user storage entry. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.user_storage_sign_prefix()
end

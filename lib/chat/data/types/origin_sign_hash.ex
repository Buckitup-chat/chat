defmodule Chat.Data.Types.OriginSignHash do
  @moduledoc "Signature hash identifying a specific version of an origin record. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.origin_sign_prefix()
end

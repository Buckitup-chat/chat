defmodule Chat.Data.Types.OriginSignHash do
  @moduledoc "Signature hash identifying a specific version of an origin record. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.origin_sign_prefix()
end

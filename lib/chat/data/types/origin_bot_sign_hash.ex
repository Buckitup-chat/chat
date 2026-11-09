defmodule Chat.Data.Types.OriginBotSignHash do
  @moduledoc "Signature hash for origin bot records. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.origin_bot_sign_prefix()
end

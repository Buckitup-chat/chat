defmodule Chat.Data.Types.OriginBotSignHash do
  @moduledoc "Signature hash for origin bot records. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.origin_bot_sign_prefix()
end

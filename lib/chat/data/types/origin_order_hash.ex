defmodule Chat.Data.Types.OriginOrderHash do
  @moduledoc "Hash identifying an origin order. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.origin_order_prefix()
end

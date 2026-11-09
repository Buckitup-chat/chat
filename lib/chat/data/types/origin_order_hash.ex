defmodule Chat.Data.Types.OriginOrderHash do
  @moduledoc "Hash identifying an origin order. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.origin_order_prefix()
end

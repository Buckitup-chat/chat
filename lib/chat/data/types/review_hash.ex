defmodule Chat.Data.Types.ReviewHash do
  @moduledoc "Unique review identifier. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.review_prefix()
end

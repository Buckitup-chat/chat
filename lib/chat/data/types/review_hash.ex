defmodule Chat.Data.Types.ReviewHash do
  @moduledoc "Unique review identifier. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.review_prefix()
end

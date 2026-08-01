defmodule Chat.Data.Schemas.ReviewPostRight do
  @moduledoc "Ecto schema for review_post_right. KEM-encrypted envelope for publishing a review."

  use Chat.Data.Schemas.ReviewRight, kind: :post
end

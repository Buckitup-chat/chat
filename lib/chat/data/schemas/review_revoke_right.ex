defmodule Chat.Data.Schemas.ReviewRevokeRight do
  @moduledoc "Ecto schema for review_revoke_right. KEM-encrypted envelope for revoking a review."

  use Chat.Data.Schemas.ReviewRight, kind: :revoke
end

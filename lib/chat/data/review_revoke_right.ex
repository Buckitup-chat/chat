defmodule Chat.Data.ReviewRevokeRight do
  @moduledoc "ReviewRevokeRight context for managing revoke rights in Postgres."

  use Chat.Data.ReviewRight, kind: :revoke
end

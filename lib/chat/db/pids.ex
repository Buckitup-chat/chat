defmodule Chat.Db.Pids do
  @moduledoc "DB pids structure"

  @enforce_keys [:main, :file]
  defstruct @enforce_keys
end

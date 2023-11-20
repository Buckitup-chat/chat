defmodule Chat.NetworkSynchronization.ErrorStatus do
  @moduledoc "Error status"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  defstruct reason: "", till: 0

  @duration_ms 300_000

  def new(reason) do
    %__MODULE__{reason: reason, till: monotonic_ms() + @duration_ms}
  end
end

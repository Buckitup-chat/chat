defmodule Chat.NetworkSynchronization.Status.SynchronizingStatus do
  @moduledoc "Error status"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  defstruct since: 0

  def new do
    %__MODULE__{since: monotonic_ms()}
  end
end

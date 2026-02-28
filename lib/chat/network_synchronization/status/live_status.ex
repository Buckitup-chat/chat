defmodule Chat.NetworkSynchronization.Status.LiveStatus do
  @moduledoc "Electric shape consumer is connected and receiving real-time updates"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  defstruct since: 0

  def new do
    %__MODULE__{since: monotonic_ms()}
  end
end

defmodule Chat.NetworkSynchronization.Status.UpdatingStatus do
  @moduledoc "Updating status"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  defstruct total: 0, done: 0, since: 0

  def new(key_list) do
    %__MODULE__{total: Enum.count(key_list), done: 0, since: monotonic_ms()}
  end

  def count_one_done(%__MODULE__{} = status) do
    status
    |> Map.put(:done, status.done + 1)
  end
end

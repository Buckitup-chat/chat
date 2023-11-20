defmodule Chat.NetworkSynchronization.CoolingStatus do
  @moduledoc "Cooling down status"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  alias Chat.NetworkSynchronization.Source

  defstruct till: 0

  @hour_ms 3600_000

  def new(%Source{} = source) do
    %__MODULE__{till: source.cooldown_hours * @hour_ms + monotonic_ms()}
  end

  def new_half(%Source{} = source) do
    %__MODULE__{till: source.cooldown_hours * @hour_ms / 2 + monotonic_ms()}
  end
end

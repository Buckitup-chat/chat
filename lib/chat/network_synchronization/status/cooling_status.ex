defmodule Chat.NetworkSynchronization.Status.CoolingStatus do
  @moduledoc "Cooling down status"

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]

  alias Chat.NetworkSynchronization.Source

  defstruct till: 0

  @hour_ms :timer.hours(1)

  def new(%Source{} = source) do
    %__MODULE__{till: source.cooldown_hours * @hour_ms + monotonic_ms()}
  end

  def new_half(%Source{} = source) do
    %__MODULE__{till: trunc(source.cooldown_hours * @hour_ms / 2) + monotonic_ms()}
  end
end

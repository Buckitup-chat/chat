defmodule Chat.NetworkSynchronization.Source do
  @moduledoc "Network source representation"

  defstruct id: nil, url: "", cooldown_hours: 1, started?: false

  def new(id) do
    %__MODULE__{id: id}
  end
end

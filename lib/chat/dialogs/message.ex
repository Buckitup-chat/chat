defmodule Chat.Dialogs.Message do
  @moduledoc "Represents single message in a dialog"

  @derive {Inspect, only: [:timestamp, :is_a_to_b?]}
  defstruct [:timestamp, :is_a_to_b?, :a_copy, :b_copy]

  def a_to_b(a_copy, b_copy, now \\ DateTime.utc_now()) do
    %__MODULE__{
      timestamp: now |> DateTime.to_unix(),
      is_a_to_b?: true,
      a_copy: a_copy,
      b_copy: b_copy
    }
  end

  def b_to_a(a_copy, b_copy, now \\ DateTime.utc_now()) do
    %__MODULE__{
      timestamp: now |> DateTime.to_unix(),
      is_a_to_b?: false,
      a_copy: a_copy,
      b_copy: b_copy
    }
  end
end

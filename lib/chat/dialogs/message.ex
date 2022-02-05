defmodule Chat.Dialogs.Message do
  @moduledoc "Represents single message in a dialog"

  use StructAccess

  @derive {Inspect, only: [:timestamp, :is_a_to_b?, :type]}
  defstruct [:timestamp, :is_a_to_b?, :a_copy, :b_copy, :type]

  def a_to_b(a_copy, b_copy, now \\ DateTime.utc_now()) do
    new(a_copy, b_copy, now: now)
  end

  def b_to_a(a_copy, b_copy, now \\ DateTime.utc_now()) do
    new(a_copy, b_copy, now: now, is_a_to_b?: false)
  end

  defp new(a_copy, b_copy, opts) do
    now = opts |> Keyword.get(:now, DateTime.utc_now())
    type = opts |> Keyword.get(:type, :text)
    is_a_to_b? = opts |> Keyword.get(:is_a_to_b?, true)

    %__MODULE__{
      timestamp: now |> DateTime.to_unix(),
      is_a_to_b?: is_a_to_b?,
      a_copy: a_copy,
      b_copy: b_copy,
      type: type
    }
  end
end

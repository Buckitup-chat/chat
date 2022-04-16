defmodule Chat.Dialogs.Message do
  @moduledoc "Represents single message in a dialog"

  use StructAccess

  @derive {Inspect, only: [:timestamp, :is_a_to_b?, :type, :id]}
  defstruct [:timestamp, :is_a_to_b?, :a_copy, :b_copy, :type, :id, version: 1]

  def a_to_b(a_copy, b_copy, opts) do
    new(a_copy, b_copy, opts |> Keyword.merge(is_a_to_b?: true))
  end

  def b_to_a(a_copy, b_copy, opts) do
    new(a_copy, b_copy, opts |> Keyword.merge(is_a_to_b?: false))
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
      type: type,
      id: UUID.uuid4()
    }
  end
end

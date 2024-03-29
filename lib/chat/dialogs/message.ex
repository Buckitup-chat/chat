defmodule Chat.Dialogs.Message do
  @moduledoc "Represents single message in a dialog"

  use StructAccess

  @derive {Inspect, only: [:timestamp, :is_a_to_b?, :type, :id]}
  defstruct [:timestamp, :is_a_to_b?, :content, :type, :id, version: 1]

  def a_to_b(content, opts) do
    new(content, opts |> Keyword.merge(is_a_to_b?: true))
  end

  def b_to_a(content, opts) do
    new(content, opts |> Keyword.merge(is_a_to_b?: false))
  end

  defp new(content, opts) do
    now = opts |> Keyword.get(:now, DateTime.utc_now())
    type = opts |> Keyword.get(:type, :text)
    id = opts |> Keyword.get(:id, UUID.uuid4())
    is_a_to_b? = opts |> Keyword.get(:is_a_to_b?, true)

    %__MODULE__{
      timestamp: now |> unixtime(),
      is_a_to_b?: is_a_to_b?,
      content: content,
      type: type,
      id: id
    }
  end

  defp unixtime(time) when is_integer(time), do: time
  defp unixtime(time), do: DateTime.to_unix(time)
end

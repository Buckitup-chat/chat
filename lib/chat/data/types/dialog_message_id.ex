defmodule Chat.Data.Types.DialogMessageId do
  @moduledoc "Dialog message identifier: \"dmsg_\" prefix + UUIDv7 with dashes. Custom Ecto type."

  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.dialog_message_prefix()
  @format ~r/^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

  @impl true
  def type, do: :string

  @impl true
  def cast(@prefix <> _rest = value) do
    if Regex.match?(@format, String.downcase(value)),
      do: {:ok, String.downcase(value)},
      else: :error
  end

  def cast(_), do: :error

  @impl true
  def dump(@prefix <> _rest = value) do
    {:ok, String.downcase(value)}
  end

  def dump(_), do: :error

  @impl true
  def load(@prefix <> _rest = value), do: {:ok, value}
  def load(_), do: :error

  def generate do
    @prefix <> String.downcase(UUIDv7.generate())
  end
end

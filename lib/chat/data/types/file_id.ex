defmodule Chat.Data.Types.FileId do
  @moduledoc "File identifier: \"f_\" prefix + UUIDv7 hex. Custom Ecto type."

  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.file_prefix()
  @expected_hex_length 32

  @impl true
  def type, do: :string

  @impl true
  def cast(@prefix <> hex_string) when byte_size(hex_string) == @expected_hex_length do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, _binary} -> {:ok, @prefix <> String.downcase(hex_string)}
      :error -> :error
    end
  end

  def cast(_), do: :error

  @impl true
  def dump(@prefix <> hex_string) do
    {:ok, @prefix <> String.downcase(hex_string)}
  end

  def dump(_), do: :error

  @impl true
  def load(@prefix <> _hex_string = value), do: {:ok, value}
  def load(_), do: :error

  def generate do
    UUIDv7.generate()
    |> String.replace("-", "")
    |> then(&(@prefix <> &1))
  end

  def from_binary(binary) when byte_size(binary) == 16 do
    @prefix <> Base.encode16(binary, case: :lower)
  end

  def to_binary(@prefix <> hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end
end

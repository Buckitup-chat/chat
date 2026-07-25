defmodule Chat.Data.Types.FileChunkDataHash do
  @moduledoc "SHA3-512 hash of raw encrypted chunk bytes. Custom Ecto type."

  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.file_chunk_data_prefix()
  @expected_hex_length 128

  @impl true
  def type, do: :string

  @impl true
  def cast(value) do
    with @prefix <> hex_string when byte_size(hex_string) == @expected_hex_length <- value,
         {:ok, _binary} <- Base.decode16(hex_string, case: :mixed) do
      {:ok, @prefix <> String.downcase(hex_string)}
    else
      _ -> :error
    end
  end

  @impl true
  def dump(@prefix <> hex_string) do
    {:ok, @prefix <> String.downcase(hex_string)}
  end

  def dump(_), do: :error

  @impl true
  def load(@prefix <> _hex_string = value), do: {:ok, value}
  def load(_), do: :error

  def from_binary(binary) when byte_size(binary) == 64 do
    @prefix <> Base.encode16(binary, case: :lower)
  end

  def to_binary(@prefix <> hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end
end

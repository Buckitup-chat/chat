defmodule Chat.Data.Types.UserStorageSignHash do
  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.user_storage_sign_prefix()
  @expected_hex_length 128

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

  @doc "Convert binary hash to string format"
  def from_binary(binary) when byte_size(binary) == 64 do
    @prefix <> Base.encode16(binary, case: :lower)
  end

  @doc "Convert string hash to binary format"
  def to_binary(@prefix <> hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end
end

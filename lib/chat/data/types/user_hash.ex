defmodule Chat.Data.Types.UserHash do
  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.user_hash_prefix()

  @impl true
  def type, do: :bytea

  @impl true
  def cast(@prefix <> _ = hash) when byte_size(hash) == 65, do: {:ok, hash}

  def cast("\\x" <> hex_data) do
    with {:ok, binary} <- Base.decode16(hex_data, case: :mixed),
         {:ok, hash} <- cast(binary) do
      {:ok, hash}
    else
      _ -> :error
    end
  end

  def cast(_), do: :error

  @impl true
  def dump(value), do: cast(value)

  @impl true
  def load(value) when is_binary(value) do
    case value do
      @prefix <> _ when byte_size(value) == 65 ->
        {:ok, value}

      "\\x" <> hex_data ->
        case Base.decode16(hex_data, case: :mixed) do
          {:ok, binary} -> cast(binary)
          :error -> :error
        end

      _ ->
        :error
    end
  end

  def load(_), do: :error
end

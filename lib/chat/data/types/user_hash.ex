defmodule Chat.Data.Types.UserHash do
  use Ecto.Type
  alias Chat.Data.Types.Consts

  @prefix Consts.user_hash_prefix()

  @impl true
  def type, do: :bytea

  @impl true
  def cast(@prefix <> _ = hash) when byte_size(hash) == 65, do: {:ok, hash}
  def cast(_), do: :error

  @impl true
  def dump(value), do: cast(value)

  @impl true
  def load(value), do: cast(value)
end

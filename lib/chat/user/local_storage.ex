defmodule Chat.User.LocalStorage do
  @moduledoc "Helpers for localStorage interaction"

  alias Chat.Identity

  def encode(%Identity{} = me, rooms) do
    %{me: me, rooms: rooms}
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def decode(data) do
    %{me: me, rooms: rooms} =
      data
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    {me, rooms} |> fix_deprecated()
  end

  defp fix_deprecated({me, rooms}) do
    {me |> fix_deprecated(), rooms |> Enum.map(&fix_deprecated/1)}
  end

  defp fix_deprecated(%{__struct__: Chat.User.Identity} = identity) do
    identity
    |> Map.put(:__struct__, Chat.Identity)
    |> fix_deprecated()
  end

  defp fix_deprecated(x), do: x
end

defmodule Chat.User.LocalStorage do
  @moduledoc "Helpers for localStorage interaction"

  alias Chat.Actor
  alias Chat.Identity

  def encode(%Identity{} = me, rooms) do
    Actor.new(me, rooms, [])
    |> Actor.to_json()
  end

  def decode(data) do
    decode_v2(data)
  rescue
    _ -> decode_v1(data)
  end

  defp decode_v2(data) do
    data
    |> Actor.from_json()
    |> then(&{&1.me, &1.rooms})
  end

  defp decode_v1(data) do
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

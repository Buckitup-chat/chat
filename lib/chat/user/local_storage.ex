defmodule Chat.User.LocalStorage do
  @moduledoc "Helpers for localStorage interaction"

  alias Chat.User.Identity

  def encode(%Identity{} = me, rooms \\ []) do
    %{me: me, rooms: rooms}
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def decode(data) do
    %{me: me, rooms: rooms} =
      data
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    {me, rooms}
  end
end

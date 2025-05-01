defmodule Chat.User.LocalStorage do
  @moduledoc "Helpers for localStorage interaction"

  alias Chat.Actor
  alias Chat.Identity

  def encode(%Identity{} = me, rooms, contacts \\ %{}, payload \\ %{}) do
    Actor.new(me, rooms, contacts, payload)
    |> Actor.to_json()
  end

  def decode(data) do
    data
    |> Actor.from_json()
    |> then(&{&1.me, &1.rooms})
  end
end

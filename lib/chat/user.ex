defmodule Chat.User do
  @moduledoc "User context"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Log
  alias Chat.User.LocalStorage
  alias Chat.User.Registry

  def login(%Identity{} = identity) do
    identity
    |> tap(&Log.visit/1)
  end

  def login(name) when is_binary(name) do
    name
    |> Identity.create()
    |> tap(&Log.sign_in/1)
  end

  def register(%Identity{} = identity), do: Registry.enlist(identity)

  def list,
    do:
      Registry.all()
      |> Map.values()
      |> Enum.sort_by(&"#{&1.name} #{&1.hash}")

  def by_id(id) do
    Registry.all()
    |> Map.get(id)
  end

  def id_map_builder(ids) do
    Registry.all()
    |> Map.split(ids)
    |> elem(0)
  end

  def device_encode(%Identity{} = identity, rooms \\ []), do: LocalStorage.encode(identity, rooms)
  def device_decode(data), do: LocalStorage.decode(data)

  def pub_key(%Card{pub_key: key}), do: key
  def pub_key(%Identity{} = identity), do: identity |> Identity.pub_key()
end

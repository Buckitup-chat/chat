defmodule Chat.User do
  @moduledoc "User context"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.User.LocalStorage
  alias Chat.User.Registry

  def login(%Identity{} = identity) do
    identity
  end

  def login(name) when is_binary(name) do
    name
    |> Identity.create()
  end

  def register(card_or_identity), do: Registry.enlist(card_or_identity)
  def await_saved(hash), do: Registry.await_saved(hash)

  def list,
    do:
      Registry.all()
      |> Map.values()
      |> Enum.sort_by(&"#{&1.name} #{&1.pub_key}")

  def by_id(id) do
    Registry.all()
    |> Map.get(id)
  end

  def id_map_builder(ids) do
    Registry.all()
    |> Map.split(ids)
    |> elem(0)
  end

  def remove(hash), do: Registry.remove(hash)

  def device_encode(%Identity{} = identity, rooms \\ [], contacts \\ %{}, payload \\ %{}) do
    LocalStorage.encode(identity, rooms, contacts, payload)
  end

  def device_decode(data), do: LocalStorage.decode(data)

  def pub_key(%Card{pub_key: key}), do: key
  def pub_key(%Identity{} = identity), do: identity |> Identity.pub_key()
end

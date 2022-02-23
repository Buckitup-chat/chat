defmodule Chat.User do
  @moduledoc "User context"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.User.LocalStorage
  alias Chat.User.Registry

  def encrypt(text, %Card{pub_key: key}), do: encrypt(text, key)
  def encrypt(text, key), do: :public_key.encrypt_public(text, key)

  def decrypt(ciphertext, %Identity{priv_key: key}) do
    :public_key.decrypt_private(ciphertext, key)
  end

  def login(%Identity{} = identity), do: identity
  def login(name) when is_binary(name), do: Identity.create(name)

  def register(%Identity{} = identity), do: Registry.enlist(identity)

  def list,
    do:
      Registry.all()
      |> Map.values()
      |> Enum.sort_by(&"#{&1.name} #{&1.hash}")

  def by_id(id) do
    Registry.all()
    |> Enum.find_value(fn {_, card} -> card.hash == id && card end)
  end

  def by_key(pub_key) do
    Registry.all()
    |> Map.get(pub_key)
  end

  def device_encode(%Identity{} = identity, rooms \\ []), do: LocalStorage.encode(identity, rooms)
  def device_decode(data), do: LocalStorage.decode(data)

  def pub_key(%Card{pub_key: key}), do: key
  def pub_key(%Identity{} = identity), do: identity |> Identity.pub_key()
end

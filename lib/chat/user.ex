defmodule Chat.User do
  @moduledoc "User context"

  alias Chat.User.Card
  alias Chat.User.Identity
  alias Chat.User.LocalStorage
  alias Chat.User.Registry

  def encrypt(text, %Card{pub_key: key}) do
    :public_key.encrypt_public(text, key)
  end

  def decrypt(ciphertext, %Identity{priv_key: key}) do
    :public_key.decrypt_private(ciphertext, key)
  end

  def login(%Identity{} = identity), do: identity
  def login(name) when is_binary(name), do: Identity.create(name)

  def register(%Identity{} = identity), do: Registry.enlist(identity)

  def list, do: Registry.all()

  def device_encode(%Identity{} = identity, rooms \\ []), do: LocalStorage.encode(identity, rooms)
  def device_decode(data), do: LocalStorage.decode(data)
end

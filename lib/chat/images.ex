defmodule Chat.Images do
  @moduledoc "Context for Image oprations"

  alias Chat.Images.Registry

  @cipher :blowfish_cfb64

  def get(key, secret) do
    blob = Registry.get(key)

    if blob do
      decrypt(blob, secret)
    end
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = encrypt(data)
    Registry.add(key, blob)

    {key, secret}
  end

  defp encrypt(data) do
    iv = 8 |> :crypto.strong_rand_bytes()
    key = 16 |> :crypto.strong_rand_bytes()

    blob = :crypto.crypto_one_time(@cipher, key, iv, data, true)

    {blob, iv <> key}
  end

  defp decrypt(data, <<iv::bits-size(64), key::bits>> = _secret) do
    :crypto.crypto_one_time(:blowfish_cfb64, key, iv, data, false)
  end
end

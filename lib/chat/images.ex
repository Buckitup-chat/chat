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

  def encrypt({data, type}) do
    iv = 8 |> :crypto.strong_rand_bytes()
    key = 16 |> :crypto.strong_rand_bytes()

    data_blob = :crypto.crypto_one_time(@cipher, key, iv, data, true)
    type_blob = :crypto.crypto_one_time(@cipher, key, iv, type, true)

    {{data_blob, type_blob}, iv <> key}
  end

  def decrypt({data_blob, type_blob} = _data, <<iv::bits-size(64), key::bits>> = _secret) do
    {
      :crypto.crypto_one_time(:blowfish_cfb64, key, iv, data_blob, false),
      :crypto.crypto_one_time(:blowfish_cfb64, key, iv, type_blob, false)
    }
  end
end

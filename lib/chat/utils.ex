defmodule Chat.Utils do
  @moduledoc "Util functions"

  alias Chat.Card
  alias Chat.Identity

  @cipher :blowfish_cfb64
  @hasher :sha3_256

  def binhash(data) do
    :crypto.hash(@hasher, binary(data))
  end

  def hash(<<_::size(256)>> = bin) do
    bin
    |> Base.encode16()
    |> String.downcase()
  end

  def hash(data) do
    data
    |> binhash()
    |> Base.encode16()
    |> String.downcase()
  end

  def page(timestamped, before, amount) do
    timestamped
    |> Enum.reduce_while({[], nil, amount}, fn
      %{timestamp: last_timestamp} = msg, {acc, last_timestamp, amount} ->
        {:cont, {[msg | acc], last_timestamp, amount - 1}}

      _, {_, _, amount} = acc when amount < 1 ->
        {:halt, acc}

      %{timestamp: timestamp} = msg, {acc, _, amount} when timestamp < before ->
        {:cont, {[msg | acc], timestamp, amount - 1}}

      _, acc ->
        {:cont, acc}
    end)
    |> then(&elem(&1, 0))
  end

  def encrypt(text, %Identity{} = identity),
    do: identity |> Identity.pub_key() |> then(&encrypt(text, &1))

  def encrypt(text, %Card{pub_key: key}), do: encrypt(text, key)
  def encrypt(text, key), do: :public_key.encrypt_public(text, key)

  def decrypt(ciphertext, %Identity{priv_key: key}) do
    :public_key.decrypt_private(ciphertext, key)
  end

  def encrypt_blob({data, type}) do
    {iv, key} = generate_key()
    data_blob = :crypto.crypto_one_time(@cipher, key, iv, data, true)
    type_blob = :crypto.crypto_one_time(@cipher, key, iv, type, true)

    {{data_blob, type_blob}, iv <> key}
  end

  def encrypt_blob(data) do
    {iv, key} = generate_key()
    data_blob = :crypto.crypto_one_time(@cipher, key, iv, data, true)

    {data_blob, iv <> key}
  end

  def decrypt_blob({data_blob, type_blob} = _data, <<iv::bits-size(64), key::bits>> = _secret) do
    {
      :crypto.crypto_one_time(@cipher, key, iv, data_blob, false),
      :crypto.crypto_one_time(@cipher, key, iv, type_blob, false)
    }
  end

  def decrypt_blob(data, <<iv::bits-size(64), key::bits>> = _secret) do
    :crypto.crypto_one_time(@cipher, key, iv, data, false)
  end

  defp binary({:RSAPublicKey, a, b}), do: "RSAPublicKey|#{a}|#{b}"
  defp binary(%Card{pub_key: key}), do: key |> binary()
  defp binary(%Identity{} = ident), do: ident |> Identity.pub_key() |> binary()

  defp binary(
         <<_::binary-size(8), ?-, _::binary-size(4), ?-, _::binary-size(4), ?-, _::binary-size(4),
           ?-, _::binary-size(12)>> = uuid
       ),
       do: UUID.string_to_binary!(uuid)

  defp binary(data) when is_binary(data), do: data

  defp generate_key do
    iv = 8 |> :crypto.strong_rand_bytes()
    key = 16 |> :crypto.strong_rand_bytes()

    {iv, key}
  end
end

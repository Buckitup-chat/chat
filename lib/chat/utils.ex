defmodule Chat.Utils do
  @moduledoc "Util functions"

  alias Chat.Card
  alias Chat.Identity

  @cipher :blowfish_cfb64
  @hasher :sha3_256

  @deprecated "use Enigma.binhash()"
  def binhash(data) do
    :crypto.hash(@hasher, binary(data))
  end

  @deprecated "use Enigma.hash()"
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

  @deprecated "use Enigma.encrypt()"
  def encrypt(text, %Identity{} = identity),
    do: identity |> Identity.pub_key() |> then(&encrypt(text, &1))

  def encrypt(text, %Card{pub_key: key}), do: encrypt(text, key)
  def encrypt(text, key), do: :public_key.encrypt_public(text, key)

  @deprecated "use Enigma.decrypt()"
  # def decrypt(ciphertext, %Identity{private_key: private, public_key: public}),
  #   do: Enigma.decrypt(ciphertext, private, public)

  # def decrypt(ciphertext, key) do
  #   :public_key.decrypt_private(ciphertext, key)
  # end

  @deprecated "use Enigma.cipher()"
  def encrypt_blob(data) when is_list(data) do
    {iv, key} = generate_key()

    data
    |> Enum.map(&:crypto.crypto_one_time(@cipher, key, iv, &1, true))
    |> then(&{&1, iv <> key})
  end

  def encrypt_blob(data) do
    {iv, key} = generate_key()
    data_blob = :crypto.crypto_one_time(@cipher, key, iv, data, true)

    {data_blob, iv <> key}
  end

  def encrypt_blob(data, <<iv::binary-size(8), key::binary-size(16), iv2::binary-size(8)>>) do
    :crypto.crypto_one_time(@cipher, key, :crypto.exor(iv, iv2), data, true)
  end

  def encrypt_blob(data, <<iv::binary-size(8), key::binary-size(16)>>) do
    :crypto.crypto_one_time(@cipher, key, iv, data, true)
  end

  @deprecated "use Enigma.decipher()"
  def decrypt_blob(data, <<iv::bits-size(64), key::bits>> = _secret) when is_list(data) do
    data |> Enum.map(&:crypto.crypto_one_time(@cipher, key, iv, &1, false))
  end

  def decrypt_blob(data, <<iv::binary-size(8), key::binary-size(16), iv2::binary-size(8)>>) do
    :crypto.crypto_one_time(@cipher, key, :crypto.exor(iv, iv2), data, false)
  end

  def decrypt_blob(data, <<iv::bits-size(64), key::bits>> = _secret) do
    :crypto.crypto_one_time(@cipher, key, iv, data, false)
  end

  @deprecated "use Enigma.encrypt_and_sign()"
  # def sign(data, %Identity{priv_key: key} = _signer), do: data |> sign(key)

  # def sign(data, private_key) do
  #   data
  #   |> binhash()
  #   |> then(&{:digest, &1})
  #   |> :public_key.sign(:none, private_key)
  # end

  @deprecated "use Enigma.decrypt_signed()"
  def is_signed_by?(sign, data, %Card{pub_key: key}), do: sign |> is_signed_by?(data, key)

  def is_signed_by?(sign, data, public_key) do
    data
    |> binhash()
    |> then(&{:digest, &1})
    |> :public_key.verify(:none, sign, public_key)
  end

  @deprecated "use Enigma.encrypt_and_sign()"
  # def encrypt_and_sign(data, for, by) do
  #   encrypted = encrypt(data, for)
  #   sign = sign(encrypted, by)

  #   {encrypted, sign}
  # end

  @deprecated "use Enigma.decrypt_signed()"
  # def decrypt_signed({encrypted, sign}, for, by) do
  #   true = is_signed_by?(sign, encrypted, by)

  #   decrypt(encrypted, for)
  # end

  @deprecated "use Enigma.generate_secret()"
  # def generate_binary_encrypt_key do
  #   {iv, key} = generate_key()

  #   iv <> key
  # end

  @deprecated "use Enigma.short_hash()"
  # def short_hash(<<_::binary-size(58)>> <> code), do: code

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

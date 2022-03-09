defmodule Chat.Utils do
  @moduledoc "Util functions"
  @cipher :blowfish_cfb64
  def hash(data) when is_binary(data) do
    data
    |> then(&:crypto.hash(:sha3_256, &1))
    |> Base.encode16()
    |> String.downcase()
  end

  def hash({:RSAPublicKey, a, b}), do: "RSAPublicKey|#{a}|#{b}" |> hash()

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

  defp generate_key do
    iv = 8 |> :crypto.strong_rand_bytes()
    key = 16 |> :crypto.strong_rand_bytes()

    {iv, key}
  end
end

defmodule Chat.Data.Integrity do
  @moduledoc """
  Signature generation and verification for data integrity.
  See docs/pq/electric/pq_data_layer/02_integrity.md
  """

  defprotocol Signable do
    @moduledoc """
    Protocol for generating signature payloads from data structures.
    """

    @doc """
    Returns a map of fields to include in the signature payload.
    Should exclude the signature field itself and any metadata.
    """
    def signable_fields(data)

    @doc """
    Returns the signing public key for verification.
    """
    def signing_key(data)

    @doc """
    Returns the signature to verify.
    """
    def signature(data)
  end

  @prefixed_hash_pattern ~r/^[a-z][a-z0-9]*_[0-9a-f]+$/

  @doc """
  Generates signature payload from any signable data structure.
  """
  def signature_payload(data) do
    data
    |> Signable.signable_fields()
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("", &encode_field/1)
  end

  @doc """
  Verifies that a signable data structure's signature matches its data.
  Returns :ok or {:error, reason}
  """
  def verify_signature(data) do
    payload = signature_payload(data)
    sign_pkey = Signable.signing_key(data)
    sign_b64 = Signable.signature(data)

    if true == EnigmaPq.verify(payload, sign_b64, sign_pkey),
      do: :ok,
      else: {:error, :invalid_signature}
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp encode_field({key, value}) do
    key_str = to_string(key)

    cond do
      String.ends_with?(key_str, "_b64") -> encode_base64(value)
      String.ends_with?(key_str, "_cert") -> encode_base64(value)
      String.ends_with?(key_str, "_pkey") -> encode_base64(value)
      String.ends_with?(key_str, "_hash") -> encode_prefixed_hash(key_str, value)
      is_list(value) -> Enum.map_join(value, "", &encode_list_element/1)
      value == true -> "true"
      value == false -> "false"
      is_nil(value) -> "null"
      is_integer(value) -> Integer.to_string(value)
      is_binary(value) -> value
      true -> to_string(value)
    end
  end

  defp encode_prefixed_hash(_key, nil), do: "null"

  defp encode_prefixed_hash(key, value) when is_binary(value) do
    if Regex.match?(@prefixed_hash_pattern, value) do
      value
    else
      raise ArgumentError,
            "signable field #{key} ends in \"_hash\" but holds #{inspect(value)}, not a " <>
              "prefixed-hex string — back it with a Chat.Data.Types.PrefixedHash-based Ecto " <>
              "type so cast/load already produce the \"prefix_hexhex...\" form the signature " <>
              "payload requires"
    end
  end

  defp encode_list_element(bin) when is_binary(bin), do: Base.encode64(bin)
  defp encode_list_element(value), do: to_string(value)

  defp encode_base64(nil), do: "null"
  defp encode_base64(value) when is_binary(value), do: Base.encode64(value)
end

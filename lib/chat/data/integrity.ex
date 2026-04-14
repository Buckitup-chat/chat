defmodule Chat.Data.Integrity do
  @moduledoc """
  Signature generation and verification for data integrity.
  Implements the algorithm from cross-server-data-integrity.livemd
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
      value == true -> "true"
      value == false -> "false"
      is_nil(value) -> "null"
      is_integer(value) -> Integer.to_string(value)
      is_binary(value) -> value
      true -> to_string(value)
    end
  end

  defp encode_base64(nil), do: "null"
  defp encode_base64(value) when is_binary(value), do: Base.encode64(value)
end

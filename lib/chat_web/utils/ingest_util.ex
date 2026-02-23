defmodule ChatWeb.Utils.IngestUtil do
  @moduledoc """
  Utilities for decoding Electric ingest payloads.

  Supports two types of binary encoding:
  - Hex-encoded fields (suffixes: _pkey, _cert, _hash): encoded as \\x... or 0x...
  - Base64-encoded fields (suffixes: _b64): encoded as base64 without padding
  """

  @doc """
  Decodes mutation fields based on suffix conventions.

  ## Parameters
  - mutations: List of mutation maps from Electric ingest
  - hex_suffixes: List of field suffixes that should be decoded as hex (e.g., ["_pkey", "_cert", "_hash"])
  - base64_suffixes: List of field suffixes that should be decoded as base64 (e.g., ["_b64"])

  ## Examples

      iex> decode_mutation_fields([mutation], ["_hash"], ["_b64"])
      {:ok, [decoded_mutation]}
  """
  def decode_mutation_fields(mutations, hex_suffixes, base64_suffixes \\ []) do
    mutations
    |> Enum.reduce_while({:ok, []}, fn mutation, {:ok, acc} ->
      case decode_mutation(mutation, hex_suffixes, base64_suffixes) do
        {:ok, mutation} -> {:cont, {:ok, [mutation | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded_mutations} -> {:ok, Enum.reverse(decoded_mutations)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_mutation(%{} = mutation, hex_suffixes, base64_suffixes) do
    ["modified", "changes", "original"]
    |> Enum.reduce_while({:ok, mutation}, fn section, {:ok, acc_mutation} ->
      case decode_section_fields(
             Map.get(acc_mutation, section),
             hex_suffixes,
             base64_suffixes
           ) do
        {:ok, nil} ->
          {:cont, {:ok, acc_mutation}}

        {:ok, decoded_section} ->
          {:cont, {:ok, Map.put(acc_mutation, section, decoded_section)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp decode_mutation(_, _hex_suffixes, _base64_suffixes), do: {:error, "invalid_payload"}

  defp decode_section_fields(section_fields, hex_suffixes, base64_suffixes)
       when is_map(section_fields) do
    Enum.reduce_while(section_fields, {:ok, %{}}, fn
      {field, value}, {:ok, acc_section} when is_binary(field) ->
        case decode_section_field(field, value, hex_suffixes, base64_suffixes) do
          {:ok, decoded_value} -> {:cont, {:ok, Map.put(acc_section, field, decoded_value)}}
          error -> {:halt, error}
        end

      {field, value}, {:ok, acc_section} ->
        {:cont, {:ok, Map.put(acc_section, field, value)}}
    end)
  end

  defp decode_section_fields(_section_fields, _hex_suffixes, _base64_suffixes), do: {:ok, nil}

  defp decode_section_field(field, value, hex_suffixes, base64_suffixes) do
    cond do
      Enum.any?(base64_suffixes, &String.ends_with?(field, &1)) ->
        decode_base64(value)

      Enum.any?(hex_suffixes, &String.ends_with?(field, &1)) ->
        decode_hex(value)

      true ->
        {:ok, value}
    end
  end

  @doc """
  Decodes hex-encoded binary fields.
  Supports both PostgreSQL format (\\x...) and alternative format (0x...).
  """
  def decode_hex(value) do
    case value do
      "\\x" <> hex -> Base.decode16(hex, case: :mixed)
      "0x" <> hex -> Base.decode16(hex, case: :mixed)
      _ -> :error
    end
    |> case do
      :error -> {:error, "invalid_hex_field"}
      {:ok, bin} -> {:ok, bin}
    end
  end

  @doc """
  Decodes base64-encoded binary fields.
  Supports both padded and unpadded base64.
  """
  def decode_base64(value) when is_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, bin} ->
        {:ok, bin}

      :error ->
        # Try with padding in case client sent padded base64
        case Base.decode64(value) do
          {:ok, bin} -> {:ok, bin}
          :error -> {:error, "invalid_base64_field"}
        end
    end
  end

  def decode_base64(_), do: {:error, "invalid_base64_field"}

  @doc """
  Legacy function for backwards compatibility.
  Decodes binary fields assuming hex encoding.
  """
  def decode_binary(binary) do
    decode_hex(binary)
  end
end


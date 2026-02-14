defmodule ChatWeb.Utils.IngestUtil do
  def decode_mutation_fields(mutations, field_suffixes) do
    mutations
    |> Enum.reduce_while({:ok, []}, fn mutation, {:ok, acc} ->
      case decode_mutation(mutation, field_suffixes) do
        {:ok, mutation} -> {:cont, {:ok, [mutation | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded_mutations} -> {:ok, Enum.reverse(decoded_mutations)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_mutation(%{} = mutation, field_suffixes) do
    ["modified", "changes", "original"]
    |> Enum.reduce_while({:ok, mutation}, fn section, {:ok, acc_mutation} ->
      case decode_section_fields(Map.get(acc_mutation, section), field_suffixes) do
        {:ok, nil} ->
          {:cont, {:ok, acc_mutation}}

        {:ok, decoded_section} ->
          {:cont, {:ok, Map.put(acc_mutation, section, decoded_section)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp decode_mutation(_, _field_suffixes), do: {:error, "invalid_payload"}

  defp decode_section_fields(section_fields, field_suffixes) when is_map(section_fields) do
    Enum.reduce_while(section_fields, {:ok, %{}}, fn
      {field, value}, {:ok, acc_section} when is_binary(field) ->
        case decode_section_field(field, value, field_suffixes) do
          {:ok, decoded_value} -> {:cont, {:ok, Map.put(acc_section, field, decoded_value)}}
          error -> {:halt, error}
        end

      {field, value}, {:ok, acc_section} ->
        {:cont, {:ok, Map.put(acc_section, field, value)}}
    end)
  end

  defp decode_section_fields(_section_fields, _field_suffixes), do: {:ok, nil}

  defp decode_section_field(field, value, field_suffixes) do
    if Enum.any?(field_suffixes, &String.ends_with?(field, &1)) do
      decode_binary(value)
    else
      {:ok, value}
    end
  end

  def decode_binary(binary) do
    case binary do
      "\\x" <> hex -> Base.decode16(hex, case: :mixed)
      "0x" <> hex -> Base.decode16(hex, case: :mixed)
      str when is_binary(str) -> {:ok, str}
      _ -> :error
    end
    |> case do
      :error -> {:error, "invalid_binary_field"}
      {:ok, bin} -> {:ok, bin}
    end
  end
end

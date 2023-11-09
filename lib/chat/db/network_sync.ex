defmodule Chat.Db.NetworkSync do
  @moduledoc "Sync from remote device"

  def all_from(api_url) do
    get_keys(api_url)
    |> reject_known()
    |> Enum.take(1)
    |> IO.inspect()
    |> get_values(api_url)
  end

  defp get_keys(base_url) do
    with query <- "query {dataKeys}",
         {:ok, %{body: body}} <- Neuron.query(query, %{}, url: base_url),
         %{"data" => %{"dataKeys" => keys}} <- body do
      keys |> Enum.map(&NaiveApi.Data.deserialize_key/1)
    else
      _ -> []
    end
    |> Enum.reject(&is_nil/1)
  end

  defp reject_known(keys) do
    keys
    |> Enum.reject(fn
      {:file_chunk, key, first, last} -> Chat.FileFs.has_file?({key, first, last})
      key -> Chat.Db.has_key?(key)
    end)
  end

  defp get_values(keys, base_url) do
    keys
    |> Enum.each(fn key ->
      with query <- "query ($key: String!) {dataValue(key: $key)}",
           serialized <- NaiveApi.Data.serialize_key(key),
           {:ok, %{body: body}} <- Neuron.query(query, %{key: serialized}, url: base_url),
           %{"data" => %{"dataValue" => raw}} <- body,
          _ <- raw |> dbg(),
           value <- NaiveApi.Data.deserialize_value(raw),
           _ <- value |> dbg(),
           false <- is_nil(value) do
        case key do
          {:file_chunk, file_key, first, last} ->
            Chat.FileFs.write_file(
              value,
              {file_key, first, last},
              CubDB.data_dir(Chat.Db.db()) <> "_files"
            )

            IO.write("=")

          _ ->
            Chat.Db.put(key, value)
            IO.write("-")
        end
      end
    end)
  end
end

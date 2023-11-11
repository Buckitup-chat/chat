defmodule Chat.Db.NetworkSync do
  @moduledoc "Sync from remote device"

  alias Chat.Db
  alias Chat.FileFs

  alias NaiveApi.Data

  def all_from(api_url) do
    get_keys(api_url)
    |> reject_known()
    |> get_values(api_url)
  end

  def load_atoms, do: load_all_chat_modules()

  defp get_keys(base_url) do
    {:ok, %{body: %{"data" => %{"dataKeys" => keys}}}} =
      Neuron.query("query {dataKeys}", %{}, url: base_url)

    keys
    |> Enum.map(&Data.deserialize_key/1)
    |> Enum.reject(&is_nil/1)
  end

  defp reject_known(keys) do
    keys
    |> Enum.reject(fn
      {:file_chunk, key, first, last} -> FileFs.has_file?({key, first, last})
      key -> Db.has_key?(key)
    end)
  end

  defp get_values(keys, base_url) do
    keys
    |> Enum.each(fn key ->
      with query <- "query ($key: String!) {dataValue(key: $key)}",
           serialized <- Data.serialize_key(key),
           {:ok, %{body: body}} <- Neuron.query(query, %{key: serialized}, url: base_url),
           %{"data" => %{"dataValue" => raw}} <- body,
           #  _ <- raw |> dbg(),
           value <- Data.deserialize_value(raw),
           #  _ <- {serialized, value} |> dbg(),
           false <- is_nil(value) do
        Chat.db_put(key, value)
      end
    end)
  end

  defp load_all_chat_modules do
    {:ok, modules} = :application.get_key(:chat, :modules)

    modules
    |> Enum.filter(&match?(["Chat" | _], Module.split(&1)))
    |> Enum.reject(&(&1 == __MODULE__))
    |> Enum.each(fn module ->
      module
      |> Code.ensure_loaded?()
    end)
  end
end

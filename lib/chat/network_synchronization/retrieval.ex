defmodule Chat.NetworkSynchronization.Retrieval do
  @moduledoc "Data retrieval"

  alias Chat.Sync.DbBrokers
  alias NaiveApi.Data

  def all_from(api_url) do
    get_keys(api_url)
    |> reject_known()
    |> get_values(api_url)
  end

  def remote_keys(url) do
    load_all_chat_modules()
    {:ok, get_keys(url)}
  rescue
    e in MatchError ->
      case e.term do
        {:error, %HTTPoison.Error{}} -> {:error, "URL is unreachable"}
        {:error, %Neuron.JSONParseError{}} -> {:error, "Not an API endpoint"}
        {:error, %Neuron.Response{}} -> {:error, "API error"}
        # coveralls-ignore-next-line
        _ -> {:error, "Unknown error in URL"}
      end

    _ ->
      {:error, "Wrong URL"}
  end

  def retrieve_key(url, remote_key), do: get_value(remote_key, url)

  def finalize do
    DbBrokers.refresh()
  end

  def reject_known(keys) do
    keys
    |> Enum.reject(&Chat.db_has?/1)
  end

  def load_all_chat_modules do
    {:ok, modules} = :application.get_key(:chat, :modules)

    modules
    |> Enum.filter(&match?(["Chat" | _], Module.split(&1)))
    |> Enum.reject(&(&1 == __MODULE__))
    |> Enum.each(fn module ->
      module
      |> Code.ensure_loaded?()
    end)
  end

  defp get_keys(base_url) do
    {:ok, %{body: %{"data" => %{"dataKeys" => keys}}}} =
      Neuron.query("query {dataKeys}", %{}, url: base_url)

    keys
    |> Enum.map(&Data.deserialize_key/1)
    |> Enum.reject(&is_nil/1)
  end

  defp get_value(key, base_url) do
    with query <- "query ($key: String!) {dataValue(key: $key)}",
         serialized <- Data.serialize_key(key),
         {:ok, %{body: body}} <- Neuron.query(query, %{key: serialized}, url: base_url),
         %{"data" => %{"dataValue" => raw}} <- body,
         #  _ <- raw |> dbg(),
         value <- Data.deserialize_value(raw),
         #  _ <- {serialized, value} |> dbg(),
         false <- is_nil(value) do
      Chat.db_put(key, value)
      :ok
    end
  end

  defp get_values(keys, base_url) do
    keys
    |> Enum.each(&get_value(&1, base_url))
  end
end

defmodule ChatSupport.Mocks.NetworkSynchronization.NeuronMockForRetrieval do
  @moduledoc "Mocks Neuron for retrieval tests by proxying to NaiveApi.Data directly"

  alias NaiveApi.Data

  def query("query {dataKeys}", %{}, url: url) do
    if local_endpoint?(url) do
      {:ok, keys} = Data.all_keys(%{}, %{})
      {:ok, %{body: %{"data" => %{"dataKeys" => keys}}}}
    else
      Neuron.query("query {dataKeys}", %{}, url: url)
    end
  end

  def query("query ($key: String!) {dataValue(key: $key)}", %{key: key}, url: url) do
    if local_endpoint?(url) do
      {:ok, value} = Data.get_value(%{key: key}, %{})
      {:ok, %{body: %{"data" => %{"dataValue" => value}}}}
    else
      Neuron.query("query ($key: String!) {dataValue(key: $key)}", %{key: key}, url: url)
    end
  end

  def query(query, variables, opts) do
    Neuron.query(query, variables, opts)
  end

  defp local_endpoint?(url), do: String.starts_with?(url, ChatWeb.Endpoint.url())
end

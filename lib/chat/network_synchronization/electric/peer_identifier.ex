defmodule Chat.NetworkSynchronization.Electric.PeerIdentifier do
  @moduledoc """
  Queries PostgreSQL system_identifier from Electric peers.

  The system_identifier is a unique 64-bit value generated when a PostgreSQL
  cluster is initialized. It persists across restarts and is more reliable
  than IP addresses for peer identification in DHCP environments.
  """

  require Logger

  @doc """
  Fetches the system_identifier from a PostgreSQL peer via Electric endpoint.

  Returns `{:ok, system_identifier}` or `{:error, reason}`.
  """
  def fetch_system_identifier(peer_url) do
    case query_system_identifier(peer_url) do
      {:ok, identifier} ->
        {:ok, identifier}

      {:error, reason} = error ->
        Logger.warning("Failed to fetch system_identifier from #{peer_url}: #{inspect(reason)}")

        error
    end
  end

  @doc """
  Queries system_identifier directly from PostgreSQL.

  Uses Electric's PostgreSQL connection to query `pg_control_system()`.
  """
  def query_system_identifier(peer_url) do
    case build_endpoint_url(peer_url) do
      {:ok, endpoint_url} ->
        query_via_http(endpoint_url)

      {:error, _reason} = error ->
        error
    end
  end

  defp build_endpoint_url(peer_url) do
    case URI.parse(peer_url) do
      %URI{scheme: scheme, host: host, port: port} when not is_nil(host) ->
        base_url = "#{scheme || "http"}://#{host}:#{port || 80}"
        {:ok, "#{base_url}/electric/v1/system_identifier"}

      _ ->
        {:error, :invalid_peer_url}
    end
  end

  defp query_via_http(endpoint_url) do
    case Req.get(endpoint_url, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: %{"system_identifier" => identifier}}} ->
        {:ok, identifier}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

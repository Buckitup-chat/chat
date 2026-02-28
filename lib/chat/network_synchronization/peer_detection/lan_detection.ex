defmodule Chat.NetworkSynchronization.PeerDetection.LanDetection do
  @moduledoc "Checks peers in a LAN for naive_api (GraphQL) and Electric shape endpoints"

  alias Chat.NetworkSynchronization

  def on_lan(ip, mask) do
    range = ip_range(ip, mask)
    port = peer_port()

    range
    |> reject_known_peers(ip)
    |> generate_urls(port)
    |> reject_offline_urls()
    |> add_urls()

    range
    |> reject_known_electric_peers(ip)
    |> generate_base_urls(port)
    |> probe_electric_peers()
    |> add_electric_urls()
  end

  defp ip_range(ip, mask) do
    prefix = IP.Prefix.from_string!("#{ip}/#{mask}")
    first = (prefix |> IP.Prefix.first() |> IP.Address.to_integer()) + 1
    last = (prefix |> IP.Prefix.last() |> IP.Address.to_integer()) - 1

    first..last
  end

  defp reject_known_peers(range, own_ip) do
    known =
      NetworkSynchronization.synchronisation()
      |> Enum.map(fn {%{url: url}, _} -> url_to_ip_integer(url) end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
      |> MapSet.put(own_ip |> IP.Address.from_string!() |> IP.Address.to_integer())

    range
    |> Enum.reject(fn ip -> MapSet.member?(known, ip) end)
  end

  defp generate_urls(range, port) do
    range
    |> Enum.map(fn ip ->
      ip
      |> IP.Address.from_integer!(4)
      |> IP.Address.to_string()
      |> then(&"http://#{&1}:#{port}/naive_api")
    end)
  end

  defp reject_offline_urls(urls) do
    urls
    |> Task.async_stream(
      fn url ->
        case Neuron.query("query {}", %{}, url: url, connection_opts: [recv_timeout: 3_000]) do
          {:ok, %Neuron.Response{status_code: 200}} -> url
          _ -> nil
        end
      end,
      max_concurrency: 1000,
      timeout: 60_000
    )
    |> Enum.reject(fn
      {:ok, nil} -> true
      {:ok, _} -> false
      _ -> true
    end)
    |> Enum.map(fn {:ok, url} -> url end)
  end

  defp add_urls(urls) do
    urls
    |> Enum.each(fn url ->
      NetworkSynchronization.add_source()
      |> Map.get(:id)
      |> NetworkSynchronization.update_source(url: url)
      |> Map.get(:id)
      |> NetworkSynchronization.start_source()
    end)
  end

  # Electric peer discovery

  defp reject_known_electric_peers(range, own_ip) do
    known =
      NetworkSynchronization.list_electric_peers()
      |> Enum.map(&url_to_ip_integer/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
      |> MapSet.put(own_ip |> IP.Address.from_string!() |> IP.Address.to_integer())

    range
    |> Enum.reject(fn ip -> MapSet.member?(known, ip) end)
  end

  defp generate_base_urls(range, port) do
    range
    |> Enum.map(fn ip ->
      ip
      |> IP.Address.from_integer!(4)
      |> IP.Address.to_string()
      |> then(&"http://#{&1}:#{port}")
    end)
  end

  defp probe_electric_peers(base_urls) do
    base_urls
    |> Task.async_stream(&probe_electric_peer/1, max_concurrency: 1000, timeout: 60_000)
    |> Enum.reject(fn
      {:ok, nil} -> true
      {:ok, _} -> false
      _ -> true
    end)
    |> Enum.map(fn {:ok, url} -> url end)
  end

  defp probe_electric_peer(base_url) do
    probe_url = "#{base_url}/electric/v1/user_card?offset=-1"

    case Req.get(probe_url, receive_timeout: 3_000) do
      {:ok, %Req.Response{status: 200, headers: headers}} ->
        if Map.has_key?(headers, "electric-handle"), do: base_url, else: nil

      _ ->
        nil
    end
  end

  defp add_electric_urls(base_urls) do
    base_urls
    |> Enum.each(&NetworkSynchronization.add_electric_peer/1)
  end

  defp peer_port do
    ChatWeb.Endpoint.config(:http)
    |> Keyword.get(:port)
  end

  defp url_to_ip_integer(url) do
    case IP.Address.from_string(url |> URI.parse() |> Map.get(:host)) do
      {:ok, ip} -> IP.Address.to_integer(ip)
      {:error, _} -> nil
    end
  end
end

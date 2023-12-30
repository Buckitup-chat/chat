defmodule Chat.NetworkSynchronization.PeerDetection.LanDetection do
  @moduledoc "Checks peers in a LAN to have naive_api endpoint"

  alias Chat.NetworkSynchronization

  def on_lan(ip, mask) do
    ip_range(ip, mask)
    |> reject_known_peers
    |> generate_urls
    |> reject_offline_urls
    |> add_urls
  end

  defp ip_range(ip, mask) do
    prefix = IP.Prefix.from_string!("#{ip}/#{mask}")
    first = (prefix |> IP.Prefix.first() |> IP.Address.to_integer()) + 1
    last = (prefix |> IP.Prefix.last() |> IP.Address.to_integer()) - 1

    first..last
  end

  defp reject_known_peers(range) do
    known =
      NetworkSynchronization.synchronisation()
      |> Enum.map(fn {%{url: url}, _} ->
        try do
          url
          |> URI.parse()
          |> Map.get(:host)
          |> IP.Address.from_string!()
          |> IP.Address.to_integer()
        rescue
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    range
    |> Enum.reject(fn ip -> MapSet.member?(known, ip) end)
  end

  defp generate_urls(range) do
    range
    |> Enum.map(fn ip ->
      ip
      |> IP.Address.from_integer!(4)
      |> IP.Address.to_string()
      |> then(&"http://#{&1}/naive_api")
    end)
  end

  defp reject_offline_urls(urls) do
    urls
    |> Task.async_stream(
      fn url ->
        try do
          {:ok, %Neuron.Response{status_code: 200}} =
            Neuron.query("query {}", %{}, url: url, connection_opts: [recv_timeout: 3_000])

          url
        rescue
          _ -> nil
        end
      end,
      max_concurrency: 100,
      timeout: 600_000
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
end

defmodule Chat.Data.File.IpfsStore do
  @moduledoc "IPFS block storage for raw encrypted chunk bytes via Kubo HTTP API."

  @default_api_url "http://127.0.0.1:5001"

  def put(binary) when is_binary(binary) do
    boundary = Base.encode16(:crypto.strong_rand_bytes(16))

    body =
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"data\"\r\nContent-Type: application/octet-stream\r\n\r\n" <>
        binary <> "\r\n--#{boundary}--\r\n"

    case Req.post(api_url("/api/v0/block/put?cid-codec=raw&mhtype=sha2-256"),
           body: body,
           headers: [{"content-type", "multipart/form-data; boundary=#{boundary}"}]
         ) do
      {:ok, %{status: 200, body: %{"Key" => cid}}} -> {:ok, cid}
      {:ok, resp} -> {:error, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  def get(cid, opts \\ []) when is_binary(cid) do
    req_opts =
      [params: [arg: cid], decode_body: false]
      |> maybe_add_timeout(opts)

    case Req.post(api_url("/api/v0/block/get"), req_opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, resp} -> {:error, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(cid) when is_binary(cid) do
    case Req.post(api_url("/api/v0/block/rm"), params: [arg: cid]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  def peer_id do
    case Req.post(api_url("/api/v0/id")) do
      {:ok, %{status: 200, body: %{"ID" => id, "Addresses" => addrs}}} ->
        {:ok, %{peer_id: id, multiaddrs: addrs || []}}

      {:ok, resp} ->
        {:error, resp.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def swarm_connect(multiaddr) when is_binary(multiaddr) do
    case Req.post(api_url("/api/v0/swarm/connect"), params: [arg: multiaddr]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  def swarm_peers do
    case Req.post(api_url("/api/v0/swarm/peers")) do
      {:ok, %{status: 200, body: %{"Peers" => peers}}} -> {:ok, peers || []}
      {:ok, resp} -> {:error, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_add_timeout(req_opts, opts) do
    case Keyword.get(opts, :receive_timeout) do
      nil -> req_opts
      timeout -> Keyword.put(req_opts, :receive_timeout, timeout)
    end
  end

  defp api_url(path) do
    Application.get_env(:chat, :ipfs_api_url, @default_api_url) <> path
  end
end

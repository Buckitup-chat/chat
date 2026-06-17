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

  def get(cid) when is_binary(cid) do
    case Req.post(api_url("/api/v0/block/get"),
           params: [arg: cid],
           decode_body: false
         ) do
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

  defp api_url(path) do
    Application.get_env(:chat, :ipfs_api_url, @default_api_url) <> path
  end
end
